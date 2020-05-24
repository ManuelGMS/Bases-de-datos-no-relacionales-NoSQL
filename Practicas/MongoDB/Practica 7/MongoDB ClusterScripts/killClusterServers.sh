#!/bin/bash

for i in `ps -ef | grep mongo | grep -v grep | cut -d " " -f 2`
do

	kill -9 $i

done
