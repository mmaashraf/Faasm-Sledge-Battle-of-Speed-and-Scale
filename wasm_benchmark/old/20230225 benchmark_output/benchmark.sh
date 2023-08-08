#!/bin/bash
ulimit -n 10000
source ./benchmark_helper.sh

HOST=node1
CONCURRENCY_START=12
CONCURRENCY_STOP=256
# CONVERGE_THRESHOLD=0.05
# CONVERGE_MIN_COUNT=5
BENCHMARK_REPEAT_COUNT=1 # number of times to run each benchmark to find an average

# TESTING
# framework=faasm
# wasm_applications=(
#     "fibonacci 25"
#     "noop"
# )
# core_counts=(16)
# connection_counts=(10000)

# BENCHMARK
framework=faasm
wasm_applications=(
    "fibonacci 25"
    "noop"
)
core_counts=(1 4 8 16 24 32 -1)
# core_counts=(1 4 16)
# core_count_interval=1 # benchmark will iterate through $core_counts then keep increasing the cores by the interval until we hit $core_max

connection_counts=(100000 150000)

benchmark_setup $HOST

for wasm_application in "${wasm_applications[@]}";
do
	read -r faasm_function faasm_input_data <<< "$wasm_application"
	for cores in ${core_counts[@]}
	do
		output_dir="benchmark_output/${framework}_${faasm_function}/workers_${cores}"
		mkdir -p $output_dir

		data_file="${framework}_${cores}_${faasm_function}"
		rm -f ${data_file} > /dev/null 2>&1
		ab_graph_data="${framework}_${faasm_function}_workers_${cores}_ab_data.csv"
		echo "connections,concurrency,ttime,rps,tpr,tpr_all,trate" >> $ab_graph_data
		for connections in ${connection_counts[@]}
		do		
			concurrency=$CONCURRENCY_START
			converge_cnt=0
			monitor_data_file="${framework}_${cores}_${faasm_function}_${connections}"
			monitor_pid=0
			while [ $concurrency -le $CONCURRENCY_STOP ]
			do
				monitor_pid=$( start_track_cpu_mem $HOST "pool_runner" ${monitor_data_file} )
				stop_faasm $HOST
				start_faasm $HOST $cores
				sleep 1 # wait for faasm to fully start
				echo "$(date '+%H:%M:%S') - Workers: $cores | App: $faasm_function | Total Requests: $connections | Request concurrency: $concurrency" | tee -a ${data_file}
				# "evenly" splits connections and concurrency between 3 apache benchmark instances to prevent ab bottleneck
				# e.g., 100 connections will be split in 34,33,33 and 16 concurrency will be split into 6,5,5
				ab_temp_file_name=$(mktemp)
				post_data=$(mktemp)
				echo "{\"user\":"demo\", \"function\":\"${faasm_function}\", \"input_data\": \"${input}\"}"" > $post_data
				ab -s 20 -n $((connections/3)) -c $((concurrency/3)) -p $post_data -T 'application/json' "http://${host}:8080/" >> $ab_temp_file_name 2>&1 &
				ab -s 20 -n $((connections/3)) -c $((concurrency/3)) -p $post_data -T 'application/json' "http://${host}:8080/" >> $ab_temp_file_name 2>&1 &
				ab -s 20 -n $((connections/3 + connections%3)) -c $((concurrency/3 + concurrency%3)) -p $post_data -T 'application/json' "http://${host}:8080/" >> $ab_temp_file_name 2>&1
				curr_rps_val=$(awk -v conn=$connections -v conc=$concurrency -v df=${data_file} -v abgd=${ab_graph_data} '
				/apr_sock/ {time_max=0; rps_sum=0; tpr_sum=0; tpr_all_sum=0; tr_sum=0; exit}
				/timeout specified/ {time_max=0; rps_sum=0; tpr_sum=0; tpr_all_sum=0; tr_sum=0; exit}
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
				echo "" >> ${data_file}

				if [ "$(echo "$curr_rps_val == 0" | bc 2>/dev/null)" == "" ]; then
					echo "bc error"
					cat $ab_temp_file_name
				elif [ "$(echo "$curr_rps_val == 0" | bc)" -eq 1 ]; then
					# Faasm crashed, restart Faasm
					echo "Faasm overloaded!"
					concurrency=999
				fi
				rm $ab_temp_file_name

				sleep 1 # faasm cooldown
				converge_cnt=$((converge_cnt+1))
				if [ $converge_cnt -lt $BENCHMARK_REPEAT_COUNT ]; then
					continue
				fi
				converge_cnt=0
				concurrency=$((concurrency+12))
			done
			# Get summary of CPU/Memory usage from framework HOST node
			stop_track_cpu_mem $HOST $monitor_pid ${monitor_data_file}
			compute_min_max_avg ${monitor_data_file} ${data_file}
			generate_cpu_mem_graphs ${monitor_data_file}
			echo
			sleep 1
		done
		stop_faasm $HOST
		generate_ab_graph_single_config ${ab_graph_data} 
		for file in "ab_graph_"*.png; do
			mv "$file" "$output_dir"
		done
		mv "${data_file}" "${data_file}_summary.txt"
		for file in "${data_file}"*; do
			mv "$file" "$output_dir"
		done
		echo
		sleep 1
	done
	generate_ab_graph_all_config $faasm_function
done
generate_ab_graph_all_apps # graph comparing all applications
move_csvs
