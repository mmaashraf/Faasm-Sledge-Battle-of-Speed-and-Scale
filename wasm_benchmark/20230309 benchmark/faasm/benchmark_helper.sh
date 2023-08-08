#!/bin/bash


function benchmark_setup() {
	sudo scp monitor.sh $1:/mydata/
	stop_faasm $1
}

function start_faasm () {
	host=$1
	core_count=$2
	echo -n "Starting Faasm with $core_count worker(s) on host $host"
	if [ "$core_count" -eq -1 ]; then
		core_count="$(grep -c ^processor /proc/cpuinfo)"
	fi
	sudo ssh $host "/bin/bash -c 'cd /mydata/faasm/;docker-compose up -d --scale worker=${core_count} nginx'" >/dev/null 2>&1
	echo "...DONE"
}

function stop_faasm () {
	host=$1
	echo -n "Stopping Faasm on host $host"
	sudo ssh $host "/bin/bash -c 'cd /mydata/faasm/;docker-compose down'" >/dev/null 2>&1
	echo "...DONE"
}

function start_track_cpu_mem () {
	# sudo scp monitor.sh $1:/mydata/
	framework=$2
	datafile="/mydata/${3}"
	# sudo ssh $1 "/bin/bash -c 'rm ${datafile}*'"
	# sudo ssh $1 "/bin/bash -c 'source /mydata/monitor.sh $framework $datafile'"
	sudo ssh $1 /bin/bash <<- EOF
	cd /mydata/
	:> /mydata/monitor
	# taskset -c 38 bash /mydata/monitor.sh $framework $datafile 1>/dev/null 2>/dev/null &
	# taskset -c 38 bash /mydata/monitor.sh $framework $datafile 1>>monitor.log 2>>monitor.log &
	# source /mydata/monitor.sh $framework $datafile 1>/dev/null 2>/dev/null &
	# tmux send-keys -t debug 'source /mydata/monitor.sh $framework ${datafile}' C-m;  # debug tmux
	# echo -1
	source /mydata/monitor.sh $framework $datafile 1>>monitor.log 2>>monitor.log &
	echo \$!
	EOF
}


function stop_track_cpu_mem () {
	echo "Stopping Monitoring script on host $1"
	# sudo ssh $1 "/bin/bash -c 'sudo kill $2'"
	sudo ssh $1 "/bin/bash -c 'rm /mydata/monitor && while [ -d /proc/$2 ] >/dev/null 2>&1; do sleep 0.1; done;'"
	datafile="/mydata/${3}"
	sudo scp "${1}:${datafile}" "."
	sudo chmod 777 $3
	sudo ssh $1 "/bin/bash -c 'sudo rm ${datafile}'"
}


function compute_min_max_avg () {
	merged_timestamp_cpumem_file=$1
	outfile=$2
	echo "Compute the min, max, average of CPU, Memory Usage"
	awk '
	BEGIN {
		cpu_min=99999;
		vmem_min=99999;
		pmem_min=99999;
		cpu_sum=0;
		vmem_sum=0;
		pmem_sum=0;
		count=0;
	}
	{
		if ($3 == "") {next;} 
		if ($4 == "") {next;} 
		if ($5 == "") {next;} 
		cpu_sum+=$3;
		vmem_sum+=$4;
		pmem_sum+=$5;
		if ($3<cpu_min) cpu_min=$3;
		if ($3>cpu_max) cpu_max=$3;
		if ($4<vmem_min) vmem_min=$4;
		if ($4>vmem_max) vmem_max=$4;
		if ($5<pmem_min) pmem_min=$5;
		if ($5>pmem_max) pmem_max=$5;
		count++;
	}
	END { 
		printf "*********** Summary over %d observations  ************\n",count;
		printf "Min of CPU: %.2f%%\n", cpu_min; 
		printf "Max of CPU: %.2f%%\n", cpu_max; 
		printf "Avg of CPU: %.2f%%\n", cpu_sum/count; 
		printf "Min of Virt Mem: %.2f Mb\n", vmem_min; 
		printf "Max of Virt Mem: %.2f Mb\n", vmem_max; 
		printf "Avg of Virt Mem: %.2f Mb\n", vmem_sum/count;
		printf "Min of Phys Mem: %.2f Mb\n", pmem_min; 
		printf "Max of Phys Mem: %.2f Mb\n", pmem_max; 
		printf "Avg of Phys Mem: %.2f Mb\n", pmem_sum/count;
		printf "\n";
	}
	' $merged_timestamp_cpumem_file >> $outfile

	awk '
		{
			sum[$1][1]+=$3 # cpu
			sum[$1][2]+=$4 # vmem
			sum[$1][3]+=$5 # pmem
			count[$1]++
			if(count[$1]==1) { # init values
				min[$1][1]=max[$1][1]=$3
				min[$1][2]=max[$1][2]=$4
				min[$1][3]=max[$1][3]=$5
			} else {
				if($3<min[$1][1]) min[$1][1]=$3
				if($4<min[$1][2]) min[$1][2]=$4
				if($5<min[$1][3]) min[$1][3]=$5
				if($3>max[$1][1]) max[$1][1]=$3
				if($4>max[$1][2]) max[$1][2]=$4
				if($5>max[$1][3]) max[$1][3]=$5
			}
		}
		END {
			for (i in sum) {
				printf("Concurrency %s\n", i)
				printf("\tCPU Min/Max/Avg: %.2f% / %.2f% / %.2f%\n", min[i][1], max[i][1], sum[i][1]/count[i])
				printf("\tVMem Min/Max/Avg: %.2f Mb / %.2f Mb / %.2f Mb\n", min[i][2], max[i][2], sum[i][2]/count[i])
				printf("\tPMem Min/Max/Avg: %.2f Mb / %.2f Mb / %.2f Mb\n", min[i][3], max[i][3], sum[i][3]/count[i])
			}
		}
	' $merged_timestamp_cpumem_file >> $outfile
	echo -e "\n\n\n" >> $outfile
}


function pct_diff () {
    if (( $(echo "$1 < $2" | bc -l) )); then
        echo $(echo "($2 - $1) / (($1 + $2) / 2)" | bc -l)
    else
        echo $(echo "($1 - $2) / (($1 + $2) / 2)" | bc -l)
    fi
}

function merge_timestamp_cpumem () {
	cpu_mem_datafile=$1
	timestamp_map_file=$2
	outfile=$(mktemp)

	mapfile -t timestamp_map <<< $(awk '{ if (prev_conc != $1) { if (NR > 1) print prev_conc, start_time, end_time; start_time=$2 } end_time=$2; prev_conc=$1 } END { print prev_conc, start_time, end_time }' < "$timestamp_map_file" )

	:> $outfile
	while read -r timestamp cpu vm pm _; do
		for line in "${timestamp_map[@]}"; do
			read concurrency start_time end_time <<< $line
			if (( timestamp >= start_time && timestamp <= end_time )); then
				echo "${concurrency} ${timestamp} $cpu $vm $pm" >> $outfile
			fi
		done
	done < $cpu_mem_datafile
	
	mv ${timestamp_map_file} "${cpu_mem_datafile}_timestamp"
	# rm -f ${cpu_mem_datafile}
	# rm -f ${timestamp_map_file}

	echo $outfile
}

function generate_cpu_mem_graphs () {
	merged_timestamp_cpumem_file=$1
	cpu_mem_datafile=$2

	python plot-cpu.py $merged_timestamp_cpumem_file "${cpu_mem_datafile}_CPU_graph"
	python plot-mem.py $merged_timestamp_cpumem_file "${cpu_mem_datafile}_MEM_graph"
}

function summarize_ab () {
	ab_temp_file_name=$1
	connections=$2
	concurrency=$3
	data_file=$4
	ab_graph_data=$5
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
	echo $curr_rps_val
}

function generate_ab_graph_single_config () {
	ab_summary_datafile=$1
	echo "Creating network graph using gnuplot for a single configuration"
	python ab_graph_single_config.py "${ab_summary_datafile}" "ab_graph"
}

function generate_ab_graph_all_config () {
	echo "Creating RPS vs core graphs for all configurations per application"
	# app_name=$1
	# python ab_graph_all_config.py $app_name
	# mv *.png "benchmark_output/faasm_${app_name}"
	python ab_graph_all_config.py
	for graph_img in *.png
	do
		application=$(basename "$graph_img" | sed 's/_[^_]*$//')
		mv $graph_img "benchmark_output/faasm_${application}"
	done
}

function generate_ab_graph_all_apps () {
	echo "Creating RPS graph to compare all apps"
	python ab_graph_all_apps.py
	mv *.png "benchmark_output"
}

function move_csvs () {
	mkdir -p "benchmark_output/csv"
	mv *.csv "benchmark_output/csv"
}






# case $1 in
	# start)
		# if [ $# -ne 4 ]; then
			# echo "incorrect number of arguments: $*"
			# echo "Usage: $0 start <host> <workers> <application>"
			# echo "Example: $0 start 10.10.1.3 4 fibonacci"
			# exit 1
		# fi
		# start_sledge $2 $3 &
		# ;;
	# stop)
		# if [ $# -ne 2 ]; then
			# echo "incorrect number of arguments: $*"
			# echo "Usage: $0 host <host>"
			# exit 1
		# fi
		# stop_sledge $2 &
		# ;;
	# *)
		# echo "invalid option: $1"
		# usage "$0"
		# exit 1
		# ;;
# esac
