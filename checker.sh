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

    details=$(egrep -A1 "${keypart}" ${watchedlog} \
              | sed -z 's/\n/|/' \
              | awk -F '"' '{print $4,$8}' )

    driver=$(echo $details \
             | egrep -o 'Name[^,]*' \
             | sed 's/Name: //')

    contenttype=$(echo $details \
                  | awk -F'/' '{print $2}' \
                  | sed 's/s//')

    contentname=$(echo $details \
                  | awk -F'/' '{print $3}')


    # Initialise the message 
    message="${message_prefix}\n"

    # Who, what, where
    message="${message}\nChecksum failed for **"${driver}"** on "${contenttype}" **"${contentname}"**"

    # Now for some more info
    [[ ${contenttype} == "track" ]] && hintfile="${contentpath}${contenttype}s/${contentname}/ui/meta_data.json"
    [[ ${contenttype} == "car" ]] && hintfile="${contentpath}${contenttype}s/${contentname}/ui/ui_car.json"
    downloadurl=$(jq -r .downloadURL ${hintfile})

    # Is this content part of a DLC pack?
    dlc="$(jq -r .${contentname} dlc)"
    [[ ${#dlc} -gt 5 ]] \
    && message="${message}\n\n${contentname} is available with the **${dlc}** DLC." \
    || /bin/true

    # Check for any notes about this content.
    # This is a rich text field, so... there be dragons.
    # Since Discord somehow can't handle hyperlinks which the WWW has had since 1988
    # we will convert links to "__text__ _(title)_" format, 
    # then create some line breaks, and strip as much other HTML as we can
    notes=$(jq -r .notes ${hintfile} \
    | tr '\r\n' ' ' \
    | sed 's|<a href="\([^"]*\)"[^>]*>\([^<]*\)</a>|__\2__ _(#@!\1!@#)_|g' \
    | sed "s|\"|'|g" \
    | sed 's|<br>|\\n|g' \
    | sed 's|<p>|\\n|g' \
    | sed 's|</p>|\\n|g' \
    | sed 's|<ul>|\\n|g' \
    | sed 's|<li>|• |g' \
    | sed 's|</li>|\\n|g' \
    | sed 's|<[^>]*>||g' \
    | sed 's|&nbsp;| |g' \
    | sed 's|#@!|<|g' \
    | sed 's|!@#|>|g' \
    | sed 's|\\|\\\\|g' \
    | sed 's|\\\\n|\\n|g' )

    # sometimes an empty save results in "<p><br></p>" so let's deal with that
    [[ "${notes}" == "\n\n\n" ]] && notes=""

    # stash this in a variable we are about to manipulate
    revised_line=${notes}

    for word in $(echo ${notes}); do
      # store any occurence of http[^ ]* into a variable "link"
      link=$(echo $word \
               | egrep -o 'http.*' \
               | sed 's|\\n$||' \
               | sed 's|__$||')
      # it is likely long URIs are sometimes hyperlinked as themselves in the notes
      # making for an extremely ugly presentation in Discord
      # referencing the formatting we built into the $notes definition above...
      # replace any occurrences of "__link__ _(link)_" with simply "link"
      revised_line=$(echo ${revised_line} \
                     | sed "s|__${link}__ _.<${link}>._|<${link}>|g")
    done

    # Now that we have cleaned up any egregious links
    # let's update that main notes variable
    notes=${revised_line}

    [[ ${#downloadurl} -gt 5 ]] \
    && message="${message}\n\n**Content download:**\n<${downloadurl}>\n" \
    || message="${message}\n\nWe don't have a download link for that. If the content is stock or DLC, make sure you have installed it, and verify your game files in Steam.\n"

    [[ ${#notes} -gt 3 ]] \
    && message="${message}\n**Important notes:**\n${notes}" \
    || /bin/true


    message="${message}\n${message_suffix}"

    payload='{"username": "'${bot_name}'", "content": "'${message}'"}'

  [[ -z ${message} ]] || curl -s -H "Content-Type: application/json" -d "${payload}" $webhookurl
  fi
  linebefore=${line}
done
