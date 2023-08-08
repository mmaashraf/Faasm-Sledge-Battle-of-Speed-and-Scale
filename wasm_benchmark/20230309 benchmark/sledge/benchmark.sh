#!/bin/bash
source ./benchmark_helper.sh

HOST=node1

MONITOR_CPU_MEM=true
CONCURRENCY_START=2
CONCURRENCY_STOP=1024
CONCURRENCY_UPDATE() { echo $(($1*2)); }
BENCHMARK_REPEAT_COUNT=4 # number of times to run each benchmark to find an average

# TESTING
# framework=sledgert
# wasm_applications=(
#     "fibonacci/bimodal 10010/fib?25"
# )
# core_counts=(16)
# spinloop_bools=(true)
# connection_counts=(150000)

# BENCHMARK
framework=sledgert
wasm_applications=(
    "fibonacci/bimodal 10010/fib?25"
    "empty/concurrency 10000/empty"
    "html 1337/index.html"
)
core_counts=(1 4 6 8 16 32)
spinloop_bools=(true false)
connection_counts=(150000)

benchmark_setup $HOST

for wasm_application in "${wasm_applications[@]}";
do
	read -r app_path app_port_and_route <<< "$wasm_application"
	application=$(echo "$app_path" | sed 's/\//_/g')
	for cores in ${core_counts[@]}
	do
		for spinlooppause_enabled in ${spinloop_bools[@]}
		do
			output_dir="benchmark_output/${framework}_${application}/workers_${cores}-spinlooppause_${spinlooppause_enabled}"
			mkdir -p $output_dir

			data_file="${framework}_${cores}_${application}"
			rm -f ${data_file} > /dev/null 2>&1
			ab_graph_data="${framework}_${application}_workers_${cores}_spinlooppause_${spinlooppause_enabled}_ab_data.csv"
			:> ${ab_graph_data}
			echo "connections,concurrency,ttime,rps,tpr,tpr_all,trate" >> $ab_graph_data
			sledge_pid=$(start_sledge $HOST $cores $app_path $spinlooppause_enabled)
			echo "Starting Sledge (${sledge_pid}) with $cores core(s) on host $HOST - application $app_path"
			for connections in ${connection_counts[@]}
			do 
				$MONITOR_CPU_MEM && monitor_data_file="${framework}_${cores}_${application}_${connections}"
				$MONITOR_CPU_MEM && monitor_pid=$( start_track_cpu_mem $HOST $framework ${monitor_data_file} )
				concurrency=$CONCURRENCY_START
				converge_cnt=0
				timestamp_map_file="timestamp_map"
				while [ $concurrency -le $CONCURRENCY_STOP ]
				do
					echo "${concurrency} $(date +%s%N)" >>  $timestamp_map_file # for cpu/mem graph start time
					echo "$(date '+%H:%M:%S') - Workers: $cores | App: $application | Spinloop Pause: $spinlooppause_enabled | Total Requests: $connections | Request concurrency: $concurrency" | tee -a ${data_file}
					# "evenly" splits connections and concurrency between 3 apache benchmark instances to prevent ab bottleneck
					# e.g., 100 connections will be split in 34,33,33 and 16 concurrency will be split into 6,5,5
					ab_temp_file_name=$(mktemp)
					ab -s 9999 -n $((connections/2 )) -c $((concurrency/2)) -T 'application/json' "$HOST:$app_port_and_route" >> $ab_temp_file_name 2>&1 &
					ab -s 9999 -n $((connections/2 + connections%2)) -c $((concurrency/2 + concurrency%2)) -T 'application/json' "$HOST:$app_port_and_route" >> $ab_temp_file_name 2>&1
					wait
					curr_rps_val=$(summarize_ab $ab_temp_file_name $connections $concurrency $data_file $ab_graph_data)
					echo "" >> ${data_file}

					if [ "$(echo "$curr_rps_val == 0" | bc)" -eq 1 ]; then
						# Sledge crashed, restart sledge
						echo "Sledge overloaded!"
						# cat $ab_temp_file_name
						sledge_pid=$(start_sledge $HOST $cores $app_path $spinlooppause_enabled)
						converge_cnt=99
						concurrency=$CONCURRENCY_STOP
					fi
					rm $ab_temp_file_name

					sleep 1
					converge_cnt=$((converge_cnt+1))
					if [ $converge_cnt -lt $BENCHMARK_REPEAT_COUNT ]; then
						continue
					fi
					echo "${concurrency} $(date +%s%N)" >>  $timestamp_map_file # for cpu/mem graph end time
					converge_cnt=0
					concurrency=$(CONCURRENCY_UPDATE $concurrency)

					sleep 1
				done
				# Get summary of CPU/Memory usage from framework HOST node
				$MONITOR_CPU_MEM && stop_track_cpu_mem $HOST $monitor_pid ${monitor_data_file}
				$MONITOR_CPU_MEM && merged_timestamp_cpumem_file=$(merge_timestamp_cpumem ${monitor_data_file} ${timestamp_map_file})
				$MONITOR_CPU_MEM && compute_min_max_avg ${merged_timestamp_cpumem_file} ${data_file}
				$MONITOR_CPU_MEM && generate_cpu_mem_graphs ${merged_timestamp_cpumem_file} ${data_file}
				$MONITOR_CPU_MEM && rm ${merged_timestamp_cpumem_file}
				echo
				sleep 1
			done
			stop_sledge $HOST $sledge_pid
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
	done
done
generate_ab_graph_all_config # graph comparing cores per application
generate_ab_graph_all_apps # graph comparing all applications
move_csvs
