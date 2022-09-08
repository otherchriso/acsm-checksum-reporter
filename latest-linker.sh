#!/usr/bin/env bash

source checksum.env

# interval in seconds between polling for log rotation
checkdelay=10

while true; do \

for dir in ${serverspath}*/assetto/logs/session/
  do \
    echo "*******"
    echo "Checking ${dir}"
    latest=$(ls -t ${dir} | grep -v 'latest' | head -1)
    echo "Latest is $latest"
    echo "source would be ${dir}${latest}"
    echo "symlink would be ${dir}latest.log"
    [[ "$(readlink ${dir}latest.log | xargs basename)" == ${latest} ]] \
      && { echo "latest.log is indeed the current file" ; } \
      || { echo "Looks like the file is new. Rotating symlink. " ; \
           unlink ${dir}latest.log ; \
           ln -s ${latest} ${dir}latest.log ; \
         }
  done
echo "Sleeping now for ${checkdelay} seconds"
echo ""
sleep ${checkdelay}
done

