#!/usr/bin/env bash

source checksum.env
source .secrets

watchedlog=${1}

tail -Fn0 "${watchedlog}" 2>&1 | \
while read line; do

  # we see the second line with reason: Checksum failed
  if [[ $(echo ${line} | egrep -c 'Kicking.*Checksum failed') -gt 0 ]]
  then
    # this assumes we didn't unluckily land halfway through a kicking 
    # which would be super dooper unlikely but still...
    keypart=$(echo ${linebefore} | awk -F '"' '{print $2".*"$4}' | sed "s/'/\.*/g" | sed 's/[-+]..:../\.*/' )

    message=$(egrep -A1 "${keypart}" ${watchedlog} \
              | sed -z 's/\n/|/' \
              | awk -F '"' '{print $4,$8}' \
              | sed -e "s/.*\(content[^']*\).*\(Name:[^,]*\),.*/\"\1\" \"\2\"/" \
              | sed "s/Name: //    " \
              | awk -F'"' '{print "Checksum failed for",$4,"on",$2}' \
              | sed 's|content/[^\/]*\/\([^\/]*\)/.*|\1|')

    details=$(egrep -A1 "${keypart}" ${watchedlog} \
              | sed -z 's/\n/|/' \
              | awk -F '"' '{print $4,$8}' )

    driver=$(echo $details | egrep -o 'Name[^,]*' | sed 's/Name: //')
    contenttype=$(echo $details | awk -F'/' '{print $2}' | sed 's/s//')
    contentname=$(echo $details | awk -F'/' '{print $3}')

    message=":police_car: :police_car: :police_car: :police_car: :police_car: :police_car: :police_car: :police_car: :police_car: :police_car: \nChecksum failed for **"${driver}"** on "${contenttype}" **"${contentname}"**"

    [[ ${contenttype} == "track" ]] && hintfile="${contentpath}${contenttype}s/${contentname}/ui/meta_data.json"
    [[ ${contenttype} == "car" ]] && hintfile="${contentpath}${contenttype}s/${contentname}/ui/ui_car.json"
    downloadurl=$(jq -r .downloadURL ${hintfile})

    [[ ${#downloadurl} -gt 5 ]] \
    && message="${message}\nTry a fresh download from:\n${downloadurl}\n\nIf that does not work it is probably the server's copy which is out of date.\nAdmins are watching and will fix that asap." \
    || message="${message}\n\nWe don't have a download link for that.\nIf the content is stock or DLC, make sure you own it, and verify your game files in Steam."

    payload='{"username": "Checksum Police", "content": "'${message}'"}'

    [[ -z ${message} ]] || curl -s -H "Content-Type: application/json" -d "${payload}" $webhookurl
  fi
  linebefore=${line}
done
