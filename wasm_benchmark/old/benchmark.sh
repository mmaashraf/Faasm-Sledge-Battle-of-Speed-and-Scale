#!/bin/bash
ulimit -n 10000
source ./benchmark_helper.sh

converge_threshold=0.10
converge_min_count=4

framework=sledgert
wasm_applications=(
    "fibonacci/bimodal 10010/fib?10"
    "empty/concurrency 10000/empty"
    "html 1337/index.html"
)
core_counts=(1 4 16 32)
# core_counts=(32) # testing
bools=(true false)
connection_counts=(1000 10000 50000 100000 150000)
# connection_counts=(1000 10000) # testing
concurrency_start=1
host=10.10.1.3

for wasm_application in "${wasm_applications[@]}";
do
	read -r app_path app_port_and_route <<< "$wasm_application"
	application=$(echo "$app_path" | sed 's/\//_/g')
	for cores in ${core_counts[@]}
	do
		for spinlooppause_enabled in ${bools[@]}
		do
			output_dir="benchmark_output/${framework}_${application}/workers_${cores}-spinlooppause_${spinlooppause_enabled}"
			mkdir -p $output_dir

			data_file="${framework}_${cores}_${application}"
			rm -f ${data_file} > /dev/null 2>&1
			ab_graph_data=$(mktemp)
			echo "connections,concurrency,ttime,rps,tpr,tpr_all,trate" >> $ab_graph_data

			start_sledge $host $cores $app_path $spinlooppause_enabled &
			sleep 2
			sledge_pid=$(ssh $host "bash -c 'pidof sledgert'")
			sleep 1
			for connections in ${connection_counts[@]}
			do 
				monitor_data_file="${framework}_${cores}_${application}_${connections}"
				monitor_pid=$( start_track_cpu_mem $host $framework ${monitor_data_file} )
				concurrency=$concurrency_start
				converge_cnt=0
				last_rps_avg=0
				rps_window=()
				while [ $converge_cnt -lt $converge_min_count ]
				do
					echo "$(date '+%H:%M:%S') - Workers: $cores | App: $application | Spinloop Pause: $spinlooppause_enabled | Total Requests: $connections | Request concurrency: $concurrency" | tee -a ${data_file}
					# "evenly" splits connections and concurrency between 3 apache benchmark instances to prevent ab bottleneck
					# e.g., 100 connections will be split in 34,33,33 and 16 concurrency will be split into 6,5,5
					ab_temp_file_name=$(mktemp)
					# -g "${monitor_data_file}_ab_${concurrency}_#"
					ab -n $((connections/3)) -c $((concurrency/3)) -T 'application/json' "$host:$app_port_and_route" >> $ab_temp_file_name 2>&1 &
					ab -n $((connections/3)) -c $((concurrency/3)) -T 'application/json' "$host:$app_port_and_route" >> $ab_temp_file_name 2>&1 &
					ab -n $((connections/3 + connections%3)) -c $((concurrency/3 + concurrency%3)) -T 'application/json' "$host:$app_port_and_route" >> $ab_temp_file_name 2>&1
					curr_rps_val=$(awk -v conn=$connections -v conc=$concurrency -v df=${data_file} -v abgd=${ab_graph_data} '
					/Time taken/ {val=$5; gsub(/\[/,"",val); time_max=time_max>val?time_max:val}
					/Requests per second/ {rps_sum += $4;} 
					/Time per request/ && !/across/ {tpr_sum += $4;} 
					/Time per request/ && /across/ {tpr_all_sum += $4;} 
					/Transfer rate/ {tr_sum += $3;} 
					END {
					print "Time taken for tests: " time_max " seconds" >> df;
					print "Requests per second: " rps_sum " [#/sec]" >> df;
					print "Time per request: " tpr_sum " [ms]" >> df;
					print "Time per request (across all concurrent requests): " tpr_all_sum " [ms]" >> df;
					print "Transfer rate: " tr_sum " [Kbytes/sec] received" >> df;
					print conn "," conc "," time_max "," rps_sum "," tpr_sum "," tpr_all_sum "," tr_sum >> abgd
					print rps_sum;
					}' $ab_temp_file_name)
					rm $ab_temp_file_name
					echo "" >> ${data_file}

					# curr_rps_val=$(echo $throughput | awk -F'Requests per second: ' '{print $2}' | awk -F' ' '{print $1}')
					rps_window+=(${curr_rps_val%.*})
					if [[ ${#rps_window[@]} -gt 3 ]]; then # only keep last 3 values
						rps_window=("${rps_window[@]:1}")
					fi
					rps_window_sum=0
					for val in "${rps_window[@]}"; do
						rps_window_sum=$((rps_window_sum + val))
					done
					rps_window_avg=$((rps_window_sum / 3))
					if (( $(echo "$(pct_diff $last_rps_avg $rps_window_avg) < $converge_threshold" | bc -l) )); then
						converge_cnt=$((converge_cnt+1))
					fi
					last_rps_avg=$rps_window_avg

					concurrency=$((concurrency*2))
					if [ $concurrency -gt $connections ] || [ $concurrency -gt 20000 ]; then
						# cannot max out framework
						concurrency=$(( $connections > 20000 ? 20000 : $connections ))
						converge_cnt=$((converge_cnt+1))
					fi
					# sleep 1
				done
				# Get summary of CPU/Memory usage from framework host node
				stop_track_cpu_mem $host $monitor_pid ${monitor_data_file}
				compute_min_max_avg ${monitor_data_file} ${data_file}
				generate_graphs ${monitor_data_file}
				echo
				sleep 1
			done
			stop_sledge $host $sledge_pid
			generate_ab_graph ${ab_graph_data}
			for file in "ab_graph_"*; do
				mv "$file" "$output_dir"
			done
			mv "${data_file}" "${data_file}_summary.txt"
			for file in "${data_file}"*; do
				mv "$file" "$output_dir"
			done
			echo
			sleep 2
		done
	done
done
