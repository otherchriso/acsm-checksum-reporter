#!/usr/bin/env bash

trap "trap - SIGTERM && kill -- -$$" SIGINT SIGTERM EXIT

source checksum.env

echo "Checksum checker started."

# Spawn the script which rotates logs every time a new server starts
$(./latest-linker.sh) &

for dir in ${serverspath}*/assetto/logs/session/; do
  $(./checker.sh ${dir}latest.log) &   
  echo "Watching ${dir}latest.log"
done


echo "here are my checker children"
echo $(jobs -p)

sleep infinity
