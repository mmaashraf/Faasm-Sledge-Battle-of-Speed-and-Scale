#!/bin/bash

sudo ssh node1 "/bin/bash -c 'sudo pkill -f sledgert'"
rm *.png
rm *.csv
rm sledgert*
rm *.log &
rm -r benchmark_output &
rm timestamp_map &
wait
