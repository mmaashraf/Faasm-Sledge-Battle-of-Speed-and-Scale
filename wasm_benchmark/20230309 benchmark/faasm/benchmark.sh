#!/bin/bash
source ./benchmark_helper.sh

HOST=node0

MONITOR_CPU_MEM=true
CONCURRENCY_START=2
CONCURRENCY_STOP=1024
# CONCURRENCY_STOP=36 # TESTING
CONCURRENCY_UPDATE() { echo $(($1*2)); }
BENCHMARK_REPEAT_COUNT=4 # number of times to run each concurrency benchmark to find an average

# BENCHMARK
framework=faasm
wasm_applications=(
    "fibonacci 25"
    "noop"
	"hello"
)
core_counts=(1 4 6 8 16 32)
# core_counts=(16 32)  # TESTING
connection_counts=(150000)
# connection_counts=(500)  # TESTING

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
			$MONITOR_CPU_MEM && monitor_data_file="${framework}_${cores}_${faasm_function}_${connections}"
			$MONITOR_CPU_MEM && monitor_pid=$( start_track_cpu_mem $HOST "pool_runner" ${monitor_data_file} )
			concurrency=$CONCURRENCY_START
			converge_cnt=0
			timestamp_map_file="timestamp_map"
			while [ $concurrency -le $CONCURRENCY_STOP ]
			do
				stop_faasm $HOST
				echo "${concurrency} $(date +%s%N)" >>  $timestamp_map_file # for cpu/mem graph start time
				sleep 2
				start_faasm $HOST $cores
				sleep 5 # wait for faasm to fully start
				echo "$(date '+%H:%M:%S') - Workers: $cores | App: $faasm_function | Total Requests: $connections | Request concurrency: $concurrency" | tee -a ${data_file}
				# "evenly" splits connections and concurrency between 3 apache benchmark instances to prevent ab bottleneck
				# e.g., 100 connections will be split in 34,33,33 and 16 concurrency will be split into 6,5,5
				ab_temp_file_name=$(mktemp)
				# ab_temp_file_name="${monitor_data_file}_${concurrency}_ab" # debugging
				post_data=$(mktemp)
				echo "{\"user\":"demo\", \"function\":\"${faasm_function}\", \"input_data\": \"${input}\"}"" > $post_data
				# ab -s 20 -n $connections -c $concurrency -p $post_data -T 'application/json' "http://${host}:8080/" >> $ab_temp_file_name 2>&1
				ab -s 20 -n $((connections/2)) -c $((concurrency/2)) -p $post_data -T 'application/json' "http://${host}:8080/" >> $ab_temp_file_name 2>&1 &
				ab -s 20 -n $((connections/2 + connections%2)) -c $((concurrency/2 + concurrency%2)) -p $post_data -T 'application/json' "http://${host}:8080/" >> $ab_temp_file_name 2>&1
				wait
				curr_rps_val=$(summarize_ab $ab_temp_file_name $connections $concurrency $data_file $ab_graph_data)
				echo "" >> ${data_file}

				if [ "$(echo "$curr_rps_val == 0" | bc)" -eq 1 ]; then
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
				echo "${concurrency} $(date +%s%N)" >>  $timestamp_map_file # for cpu/mem graph end time
				converge_cnt=0
				concurrency=$(CONCURRENCY_UPDATE $concurrency)

				sleep 2
			done
			# Get summary of CPU/Memory usage from framework HOST node
			$MONITOR_CPU_MEM && stop_track_cpu_mem $HOST $monitor_pid ${monitor_data_file}
			$MONITOR_CPU_MEM && merged_timestamp_cpumem_file=$(merge_timestamp_cpumem ${monitor_data_file} ${timestamp_map_file})
			$MONITOR_CPU_MEM && compute_min_max_avg ${merged_timestamp_cpumem_file} ${data_file}
			$MONITOR_CPU_MEM && generate_cpu_mem_graphs ${merged_timestamp_cpumem_file} ${data_file}
			$MONITOR_CPU_MEM && rm ${merged_timestamp_cpumem_file}
			echo
			sleep 2
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
		sleep 2
	done
done
generate_ab_graph_all_config # graph comparing cores per application
generate_ab_graph_all_apps # graph comparing application rps per cores
move_csvs
