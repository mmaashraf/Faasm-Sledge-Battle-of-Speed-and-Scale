#!/bin/bash


function start_sledge () {
	scp monitor.sh $1:/mydata/
	ssh $1 "/bin/bash -c 'sudo pkill -f sledgert'"
	echo "Starting Sledge with $2 core(s) on host $1 - application $3"
	ssh $1 /bin/bash <<- EOF
	export SLEDGE_NWORKERS=$2
	export SLEDGE_SPINLOOP_PAUSE_ENABLED=$4
	cd /mydata/sledge-serverless-framework/runtime/bin/
	sudo LD_LIBRARY_PATH="$(pwd):$LD_LIBRARY_PATH" ./sledgert ../../tests/$3/spec.json
	EOF
}


function stop_sledge () {
	echo "Stopping Sledge on host $1"
	ssh $1 "/bin/bash -c 'sudo kill $2'"
}


function start_track_cpu_mem () {
	# scp monitor.sh $1:/mydata/
	framework=$2
	datafile="/mydata/${3}"
	# ssh $1 "/bin/bash -c 'rm ${datafile}*'"
	# ssh $1 "/bin/bash -c 'source /mydata/monitor.sh $framework $datafile'"
	ssh $1 /bin/bash <<- EOF
	rm ${datafile}* > /dev/null 2>&1 &
	source /mydata/monitor.sh $framework $datafile 1>/dev/null 2>/dev/null &
	echo \$!
	EOF
}


function stop_track_cpu_mem () {
	echo "Stopping Monitoring script on host $1"
	ssh $1 "/bin/bash -c 'sudo kill $2'"
	datafile="/mydata/${3}"
	scp "${1}:${datafile}" "."
	ssh $1 "/bin/bash -c 'sudo rm ${datafile}'"
}


function pct_diff () {
    if (( $(echo "$1 < $2" |bc -l) )); then
        echo $(echo "($2 - $1) / (($1 + $2) / 2)" | bc -l)
    else
        echo $(echo "($1 - $2) / (($1 + $2) / 2)" | bc -l)
    fi
}

function generate_graphs () {
	cpu_mem_datafile=$1
	iter_count=$(wc -l < ${cpu_mem_datafile})

	echo "Creating Memory graph using gnuplot"
	gnuplot -e "
	set term png;
	set output '${cpu_mem_datafile}_Memory_graph.png';
	set title 'Memory Usage';
	set xlabel 'Over $iter_count Iterations ';
	set ylabel 'Usage (MB)';
	plot '${cpu_mem_datafile}' using 1:3 with linespoints pt 7 title 'Memory';
	"

	echo "Creating CPU graph using gnuplot"
	gnuplot -e "
	set term png;
	set output '${cpu_mem_datafile}_CPU_graph.png';
	set title 'CPU Usage';
	set xlabel 'Over $iter_count Iterations ';
	set ylabel 'Usage (%)';
	plot '${cpu_mem_datafile}' using 1:2 with linespoints pt 7 title 'CPU';
	"

	rm ${cpu_mem_datafile}

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

function generate_ab_graph () {
	ab_summary_datafile=$1
	echo "Creating network graph using gnuplot"
	python ab_graph.py "${ab_summary_datafile}" "ab_graph"
	rm $ab_summary_datafile
}

function compute_min_max_avg () {
	# echo "Compute the min, max, average of CPU, Memory Usage"
	awk '
	BEGIN {
		min1=99999999999;
		min2=99999999999;
		sum1=0;
		sum2=0;
		count=0;
	}
	{
	if ($2 == "") {next;} 
	if ($3 == "") {next;} 
		sum1+=$2;
		sum2+=$3;
		if ($2<min1) min1=$2;
		if ($3<min2) min2=$3;
		if ($2>max1) max1=$2;
		if ($3>max2) max2=$3;
		count++;
	}
	END { 
	printf "*********** Summary over %d observations  ************\n",count;
	printf "Min of CPU: %.2f\n", min1; 
	printf "Max of CPU: %.2f\n", max1; 
	printf "Avg of CPU: %.2f\n", sum1/count; 
	printf "Min of Memory (MBs): %.2f\n", min2; 
	printf "Max of Memory (MBs): %.2f\n", max2; 
	printf "Avg of Memory (MBs): %.2f\n", sum2/count;
	printf "\n\n\n";
	}' $1 >> $2
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
