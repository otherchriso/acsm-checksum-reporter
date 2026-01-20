#!/usr/bin/env bash

# Check required commands
if ! command -v jq &> /dev/null; then
  echo "Error: jq is required but not installed." >&2
  exit 1
fi

if ! command -v curl &> /dev/null; then
  echo "Error: curl is required but not installed." >&2
  exit 1
fi

# Check required config files
if [[ ! -f checksum.env ]]; then
  echo "Error: checksum.env not found." >&2
  exit 1
fi

if [[ ! -f .secrets ]]; then
  echo "Error: .secrets not found." >&2
  exit 1
fi

source checksum.env
source .secrets

# Validate required environment variables
if [[ -z "${contentpath}" ]]; then
  echo "Error: contentpath is not set in checksum.env." >&2
  exit 1
fi

if [[ -z "${message_prefix}" ]]; then
  echo "Error: message_prefix is not set in checksum.env." >&2
  exit 1
fi

if [[ -z "${message_suffix}" ]]; then
  echo "Error: message_suffix is not set in checksum.env." >&2
  exit 1
fi

if [[ -z "${bot_name}" ]]; then
  echo "Error: bot_name is not set in checksum.env." >&2
  exit 1
fi

if [[ -z "${webhookurl}" ]]; then
  echo "Error: webhookurl is not set in .secrets." >&2
  exit 1
fi

# Validate argument
if [[ -z "${1}" ]]; then
  echo "Usage: $0 <logfile>" >&2
  exit 1
fi

watchedlog="${1}"

# Check log file exists and is readable
if [[ ! -f "${watchedlog}" ]]; then
  echo "Error: Log file '${watchedlog}' not found." >&2
  exit 1
fi

if [[ ! -r "${watchedlog}" ]]; then
  echo "Error: Log file '${watchedlog}' is not readable." >&2
  exit 1
fi

tail -Fn0 "${watchedlog}" 2>&1 | \
while read -r line; do

  # we see the second line with reason: Checksum failed
  if [[ $(echo "${line}" | egrep -c 'Kicking.*Checksum failed') -gt 0 ]]
  then
    # this assumes we didn't unluckily land halfway through a kicking 
    # which would be super dooper unlikely but still...
    keypart=$(echo "${linebefore}" | awk -F '"' '{print $2".*"$4}' | sed "s/'/.*/g" | sed 's/[-+]..:../.*/') 

    details=$(egrep -A1 "${keypart}" "${watchedlog}" \
              | sed -z 's/\n/|/' \
              | awk -F '"' '{print $4,$8}' )

    driver=$(echo "${details}" \
             | egrep -o 'Name[^,]*' \
             | sed 's/Name: //')

    contenttype=$(echo "${details}" \
                  | awk -F'/' '{print $2}' \
                  | sed 's/s//')

    contentname=$(echo "${details}" \
                  | awk -F'/' '{print $3}')


    # Initialise the message 
    message="${message_prefix}\n"

    # Who, what, where
    message="${message}\nChecksum failed for **"${driver}"** on "${contenttype}" **"${contentname}"**"

    # Now for some more info
    [[ ${contenttype} == "track" ]] && hintfile="${contentpath}${contenttype}s/${contentname}/ui/meta_data.json"
    [[ ${contenttype} == "car" ]] && hintfile="${contentpath}${contenttype}s/${contentname}/ui/ui_car.json"
    
    # Check if hintfile exists before reading
    if [[ -f "${hintfile}" ]]; then
      downloadurl=$(jq -r .downloadURL "${hintfile}" | xargs)
    else
      downloadurl=""
    fi

    # Is this content part of a DLC pack?
    if [[ -f dlc ]]; then
      dlc="$(jq -r .${contentname} dlc)"
    else
      dlc=""
    fi
    [[ ${#dlc} -gt 5 ]] \
    && message="${message}\n\n${contentname} is available with the **${dlc}** DLC." \
    || /bin/true

    # Check for any notes about this content.
    # This is a rich text field, so... there be dragons.
    # Since Discord somehow can't handle hyperlinks which the WWW has had since 1988
    # we will convert links to "__text__ _(title)_" format, 
    # then create some line breaks, and strip as much other HTML as we can
    if [[ -f "${hintfile}" ]]; then
      notes=$(jq -r .notes "${hintfile}" \
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
    else
      notes=""
    fi

    # sometimes an empty save results in "<p><br></p>" so let's deal with that
    [[ "${notes}" == "\n\n\n" ]] && notes=""

    # stash this in a variable we are about to manipulate
    revised_line="${notes}"

    for word in $(echo "${notes}"); do
      # store any occurence of http[^ ]* into a variable "link"
      link=$(echo "${word}" \
               | egrep -o 'http.*' \
               | sed 's|\\n$||' \
               | sed 's|__$||')
      # it is likely long URIs are sometimes hyperlinked as themselves in the notes
      # making for an extremely ugly presentation in Discord
      # referencing the formatting we built into the $notes definition above...
      # replace any occurrences of "__link__ _(link)_" with simply "link"
      revised_line=$(echo "${revised_line}" \
                     | sed "s|__${link}__ _.<${link}>._|<${link}>|g")
    done

    # Now that we have cleaned up any egregious links
    # let's update that main notes variable
    notes="${revised_line}"

    [[ ${#downloadurl} -gt 5 ]] \
    && message="${message}\n\n**Content download:**\n<${downloadurl}>\n" \
    || message="${message}\n\nWe don't have a download link for that. If the content is stock or DLC, make sure you have installed it, and verify your game files in Steam.\n"

    [[ ${#notes} -gt 3 ]] \
    && message="${message}\n**Important notes:**\n${notes}" \
    || /bin/true


    message="${message}\n${message_suffix}"

    payload='{"username": "'${bot_name}'", "content": "'${message}'"}'

    if [[ -n "${message}" ]]; then
      if ! curl -sf -H "Content-Type: application/json" -d "${payload}" "${webhookurl}"; then
        echo "Warning: Failed to send webhook notification for ${driver} on ${contentname}" >&2
      fi
    fi
  fi
  linebefore="${line}"
done
