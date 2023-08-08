#!/bin/bash


function benchmark_setup() {
	sudo scp monitor.sh $1:/mydata/
}


function start_sledge () {
	sudo ssh $1 "/bin/bash -c 'sudo pkill -f sledgert'"
	core_count=$2
	nworkers_cmd="export SLEDGE_NWORKERS=$core_count"
	if [ "$cores" -eq -1 ]; then
		nworkers_cmd="unset SLEDGE_NWORKERS"
		core_count="ALL"
	fi
	sudo ssh $1 /bin/bash <<- EOF
		$nworkers_cmd
		export SLEDGE_SPINLOOP_PAUSE_ENABLED=$4
		cd /mydata/sledge-serverless-framework/runtime/bin/
		sudo LD_LIBRARY_PATH="$(pwd):$LD_LIBRARY_PATH" ./sledgert ../../tests/$3/spec.json > /mydata/sledgert.out 2>&1 &
		echo \$! > /mydata/sledgert.pid
	EOF
	sleep 2
	sledge_pid=$(sudo ssh $1 "cat /mydata/sledgert.pid")
	echo "Starting Sledge (${sledge_pid}) with $core_count core(s) on host $1 - application $3" >&2
	echo $sledge_pid
}


function stop_sledge () {
	echo "Stopping Sledge ($2) on host $1"
	sudo ssh $1 "/bin/bash -c 'sudo kill $2'"
}


function start_track_cpu_mem () {
	# sudo scp monitor.sh $1:/mydata/
	framework=$2
	datafile="/mydata/${3}"
	# sudo ssh $1 "/bin/bash -c 'rm ${datafile}*'"
	# sudo ssh $1 "/bin/bash -c 'source /mydata/monitor.sh $framework $datafile'"
	sudo ssh $1 /bin/bash <<- EOF
	taskset -c 38 bash /mydata/monitor.sh $framework $datafile 1>/dev/null 2>/dev/null &
	# source /mydata/monitor.sh $framework $datafile 1>/dev/null 2>/dev/null &
	echo \$!
	EOF
}


function stop_track_cpu_mem () {
	echo "Stopping Monitoring script on host $1"
	sudo ssh $1 "/bin/bash -c 'sudo kill $2'"
	datafile="/mydata/${3}"
	sudo scp "${1}:${datafile}" "."
	sudo ssh $1 "/bin/bash -c 'sudo rm ${datafile}'"
}


function compute_min_max_avg () {
	# echo "Compute the min, max, average of CPU, Memory Usage"
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
		if ($2 == "") {next;} 
		if ($3 == "") {next;} 
		if ($4 == "") {next;} 
		cpu_sum+=$2;
		vmem_sum+=$3;
		pmem_sum+=$4;
		if ($2<cpu_min) cpu_min=$2;
		if ($2>cpu_max) cpu_max=$2;
		if ($3<vmem_min) vmem_min=$3;
		if ($3>vmem_max) vmem_max=$3;
		if ($4<pmem_min) pmem_min=$4;
		if ($4>pmem_max) pmem_max=$4;
		count++;
	}
	END { 
	printf "*********** Summary over %d observations  ************\n",count;
	printf "Min of CPU: %.2f\n", cpu_min; 
	printf "Max of CPU: %.2f\n", cpu_max; 
	printf "Avg of CPU: %.2f\n", cpu_sum/count; 
	printf "Min of Virt Mem (MBs): %.2f\n", vmem_min; 
	printf "Max of Virt Mem (MBs): %.2f\n", vmem_max; 
	printf "Avg of Virt Mem (MBs): %.2f\n", vmem_sum/count;
	printf "Min of Phys Mem (MBs): %.2f\n", pmem_min; 
	printf "Max of Phys Mem (MBs): %.2f\n", pmem_max; 
	printf "Avg of Phys Mem (MBs): %.2f\n", pmem_sum/count;
	printf "\n\n\n";
	}' $1 >> $2
}


function pct_diff () {
    if (( $(echo "$1 < $2" | bc -l) )); then
        echo $(echo "($2 - $1) / (($1 + $2) / 2)" | bc -l)
    else
        echo $(echo "($1 - $2) / (($1 + $2) / 2)" | bc -l)
    fi
}

function generate_cpu_mem_graphs () {
	cpu_mem_datafile=$1
	timestamp_map_file=$2
	iter_count=$(wc -l < ${cpu_mem_datafile})

	echo "Creating CPU graph using gnuplot"
	gnuplot -e "
	set term png;
	set output '${cpu_mem_datafile}_CPU_graph.png';
	set title 'CPU Usage';
	set xlabel 'Over $iter_count Iterations ';
	set ylabel 'Usage (%)';
	plot '${cpu_mem_datafile}' using 0:2 with linespoints pt 7 title 'CPU';
	"

	echo "Creating Memory graph using gnuplot"
	gnuplot -e "
	set term png;
	set output '${cpu_mem_datafile}_Memory_graph.png';
	set title 'Memory Usage';
	set xlabel 'Over $iter_count Iterations ';
	set ylabel 'Usage (MB)';
	plot '${cpu_mem_datafile}' using 0:3 with linespoints pt 7 title 'Virt Memory', '${cpu_mem_datafile}' using 0:4 with linespoints pt 7 title 'Phys Memory';
	"

	# rm -f ${cpu_mem_datafile}
	mv ${timestamp_map_file} "${cpu_mem_datafile}_timestamp"
	# rm -f ${timestamp_map_file}

	# echo "Creating network graph using gnuplot"
	# ab_temp=$(mktemp)
	# for file in "${cpu_mem_datafile}_ab_"*; do
		# tail -n +2 "$file" >> "$ab_temp"
		# rm $file
	# done
	# gnuplot -e "
	# set term png;
	# set output '${cpu_mem_datafile}_ab_graph.png';
	# set title 'Request Response Time';
	# set grid y;
	# set xlabel 'Request unix time';
	# set ylabel 'Response time (ms)';
	# set yrange [0:100];
	# plot '$ab_temp' using 6:7 smooth sbezier with lines title 'ctime', '$ab_temp' using 6:8 smooth sbezier with lines title 'dtime', '$ab_temp' using 6:9 smooth sbezier with lines title 'ttime', '$ab_temp' using 6:10 smooth sbezier with lines title 'wait';"
	# rm $ab_temp
}

function generate_ab_graph_single_config () {
	ab_summary_datafile=$1
	echo "Creating network graph using gnuplot for a single configuration"
	python ab_graph_single_config.py "${ab_summary_datafile}" "ab_graph"
}

function generate_ab_graph_all_config () {
	echo "Creating RPS vs core graphs for all configurations per application"
	app_name=$1
	python ab_graph_all_config.py
	# mv "${app_name}"*".png" "benchmark_output/sledgert_${app_name}"
	mv *.png "benchmark_output/sledgert_${app_name}"
}

function generate_ab_graph_all_apps () {
	echo "Creating RPS graph to compare all apps"
	python ab_graph_all_apps.py
	mv *.png "benchmark_output"
}

function move_csvs () {
	mkdir "benchmark_output/csv"
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
