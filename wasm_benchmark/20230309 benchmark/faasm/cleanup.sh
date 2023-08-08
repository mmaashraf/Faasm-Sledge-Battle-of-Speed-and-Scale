#!/bin/bash

. benchmark_helper.sh
stop_faasm node1
rm *.png &
rm *.csv &
rm faasm* &
rm *.log &
rm -r benchmark_output &
rm timestamp_map &
wait
