#!/bin/bash

cd /mydata/
process_name=$1
out_data_file=$2
TIMEOUT=3 #seconds

while ! pid=$(pidof $process_name); do
    echo "$(date) No processes found with name: $process_name"
    sleep 0.2
done

echo "$(date) Monitoring process ${process_name}"

rm *.out # for script interrupts
while [ -f /mydata/monitor ]; do
    # check if all processes have stopped
    framework_pids=($(pidof -- "$process_name"))
    echo "$(date) ${#framework_pids[@]} ${framework_pids[@]}"
    if [ -z "$framework_pids" ]; then
        sleep 0.5
        continue
    fi

    pid_list=()
    for pid in "${framework_pids[@]}"; do
        if [ -e /proc/"$pid"/stat ]; then
            # ( { top -b -p $pid -n 1 | grep 'Cpu(s)' | awk '{print $2 + $4 " "}' | tr "\n" " "; sudo pmap -x $pid | tail -n 1 | awk '{print $3/1024,$4/1024}'; } > "$pid.out" & )
            # ( { top -b -n1 | grep $pid | awk '{ printf $9 " " }'; sudo pmap -x $pid | tail -n 1 | awk '{print $3/1024,$4/1024}'; } > "$pid.out" & )
            ( { awk '{ printf ""($14+$15)/($14+$15+$16+$17)*100" "}' /proc/$pid/stat || echo "0 "; sudo pmap -x $pid | tail -n 1 | awk '{print $3/1024,$4/1024}'; } > "$pid.out" & )
            pid_list+=($pid)
        fi
    done

    cpu_sum=0
    pmem_sum=0
    vmem_sum=0
    timeout_start=$(date +%s)
    # wait for processes to finish
    while [ ${#pid_list[@]} -ne 0 ] && [ -f /mydata/monitor ] && (( $(date +%s) - timeout_start < TIMEOUT )); do
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
                fi
            fi
        done
    done
    if [[ $(( $(date +%s) - timeout_start )) > 1 ]]; then
        echo $(date) -- $(( $(date +%s) - timeout_start ))
    fi
    rm *.out

    # if mem are valid numbers, save to file
    if [ "$vmem_sum" != 0 ] && [ "$pmem_sum" != 0 ]; then
        echo "$(date +%s%N) $cpu_sum $vmem_sum $pmem_sum" >> ${out_data_file}
    fi
done
echo "$(date) Done!"
