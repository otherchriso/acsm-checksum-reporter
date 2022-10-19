#!/usr/bin/env bash

source checksum.env

# interval in seconds between polling for log rotation
checkdelay=10

while true; do \

for dir in ${serverspath}*/assetto/logs/session/
  do \
    echo "*******"
    echo "Checking ${dir}"
    latest=$(ls -t ${dir} | grep -v 'latest.log' | head -1)
    [[ -f "${dir}${latest}" ]] \
      && { echo "Latest is ${latest}" ; \
           echo "source would be ${dir}${latest}" ; \
           echo "symlink would be ${dir}latest.log" ; } \
      || echo "There does not seem to be a latest results file."
    [[ ( -L "${dir}latest.log" && "$(readlink ${dir}latest.log | xargs basename)" == ${latest} ) ]] \
      && { echo "'latest.log' is indeed linked to the most recent file" ; } \
      || { echo "Will update 'latest.log' symlink, assuming this server has a log file at all." ; \
           [[ -L "${dir}latest.log" ]] && unlink ${dir}latest.log ; \
           [[ -f "${dir}${latest}" ]] && ln -s ${latest} ${dir}latest.log ; \
         }
  done
echo "Sleeping now for ${checkdelay} seconds"
echo ""
sleep ${checkdelay}
done

