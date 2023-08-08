#!/bin/bash

cd /mydata/
process_name=$1
data_file=$2
pids=$(pidof $process_name)

if [ -z "$pids" ]; then
  echo "No processes found with name: $process_name"
  exit 1
fi

echo "Monitoring processes with pids: $pids"

rm *.out
while true; do
    # check if all processes have stopped
    if ! pidof "$process_name" >& /dev/null
    then
        break
    fi

    pid_list=()
    for pid in $pids; do
        # ( { top -b -p $pid -n 1 | awk 'NR>7 { printf $9 " " }'; sudo pmap -x $pid | tail -n 1 | awk '{print $3/1024,$4/1024}'; } > "$pid.out" & )
        ( { ps -p $pid -o %cpu | tail -n 1 | bc | tr "\n" " "; sudo pmap -x $pid | tail -n 1 | awk '{print $3/1024,$4/1024}'; } > "$pid.out" & )
        pid_list+=($pid)
    done

    cpu_sum=0
    pmem_sum=0
    vmem_sum=0
    # wait for processes to finish
    while [ ${#pid_list[@]} -ne 0 ]; do
        for pid_idx in "${!pid_list[@]}"; do
            curr_pid=${pid_list[pid_idx]}
            if [ -s "${curr_pid}.out" ]; then
                # process has finished
                read cpu vmem pmem < ${curr_pid}.out
                if [ ! -z "$cpu" ] && [ ! -z "$vmem" ] && [ ! -z "$pmem" ]; then
                    cpu_sum=$(echo "$cpu_sum + $cpu" | bc -l)
                    vmem_sum=$(echo "$vmem_sum + $vmem" | bc -l)
                    pmem_sum=$(echo "$pmem_sum + $pmem" | bc -l)
                    unset 'pid_list[pid_idx]'
                    rm "${curr_pid}.out"
                fi
            fi
        done
    done

    # if cpu/mem are valid numbers, save to file
    # if [[ "$cpu_sum" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
    if [ "$vmem_sum" != 0 ] && [ "$pmem_sum" != 0 ]; then
        echo "$(date +%s%N) $cpu_sum $vmem_sum $pmem_sum" >> ${data_file}
    fi
done
