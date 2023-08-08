#!/bin/bash
# sudo apt-get install gnuplot

process_name=$1
pid=$(pidof $process_name)
# pid=$1

if [ -z "$pid" ]; then
  echo "Process '$process_name' not found"
  exit 1
fi

echo "Monitoring process '$process_name' (pid $pid)..."

i=0
data_file=$2

while true; do
	if ! pidof "$process_name" >& /dev/null # if framework has stopped
	then
		break
	fi
	cpu=$(top -b -p $pid -n 1 | awk 'NR>7 { print $9 }')
	# memory=$(sudo pmap $pid | awk 'NR==2 { print $2 }')
	#memory=$(sudo pmap $pid | awk '/total/{print substr($2, 0, length($2) - 1)}')
	# convert KBs to MBs
	# memory=$(sudo pmap $pid |awk '/total/{printf "%.2f\n", $2/1024}')
	# memory=$(sudo pmap -x $pid | tail -n 1 | awk '{print $3/1024}') # total mb
	memory=$(sudo pmap -x $pid | tail -n 1 | awk '{print $4/1024}') # rss mb
	echo "$i $cpu $memory" >> ${data_file}
	i=$((i+1))
done

# graphs and summary moved to benchmark_helper.sh to be performed on benchmark machine
# tail -7 $data_file #output
