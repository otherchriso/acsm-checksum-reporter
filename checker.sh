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

# Send a message to the Discord webhook
# Arguments: $1 = message, $2 = context for error logging
send_webhook() {
  local message="${1}"
  local context="${2}"
  local payload='{"username": "'${bot_name}'", "content": "'${message}'"}'

  if [[ -n "${message}" ]]; then
    if ! curl -sf -H "Content-Type: application/json" -d "${payload}" "${webhookurl}"; then
      echo "Warning: Failed to send webhook notification for ${context}" >&2
    fi
  fi
}

# Prepare message for checksum validation failure
# Arguments: $1 = line before the trigger, $2 = watchedlog path
# Outputs: message via echo
prepare_checksum_message() {
  local linebefore="${1}"
  local watchedlog="${2}"
  local message=""

  # this assumes we didn't unluckily land halfway through a kicking 
  # which would be super dooper unlikely but still...
  local keypart=$(echo "${linebefore}" | awk -F '"' '{print $2".*"$4}' | sed "s/'/.*/g" | sed 's/[-+]..:../.*/') 

  local details=$(egrep -A1 "${keypart}" "${watchedlog}" \
            | sed -z 's/\n/|/' \
            | awk -F '"' '{print $4,$8}' )

  local driver=$(echo "${details}" \
           | egrep -o 'Name[^,]*' \
           | sed 's/Name: //')

  local contenttype=$(echo "${details}" \
                | awk -F'/' '{print $2}' \
                | sed 's/s//')

  local contentname=$(echo "${details}" \
                | awk -F'/' '{print $3}')

  # Initialise the message 
  message="${message_prefix}\n"

  # Who, what, where
  message="${message}\nChecksum failed for **${driver}** on ${contenttype} **${contentname}**"

  # Now for some more info
  local hintfile=""
  [[ ${contenttype} == "track" ]] && hintfile="${contentpath}${contenttype}s/${contentname}/ui/meta_data.json"
  [[ ${contenttype} == "car" ]] && hintfile="${contentpath}${contenttype}s/${contentname}/ui/ui_car.json"
  
  # Check if hintfile exists before reading
  local downloadurl=""
  if [[ -f "${hintfile}" ]]; then
    downloadurl=$(jq -r .downloadURL "${hintfile}" | xargs)
  fi

  # Is this content part of a DLC pack?
  local dlc=""
  if [[ -f dlc ]]; then
    dlc="$(jq -r ".${contentname}" dlc)"
  fi
  [[ ${#dlc} -gt 5 ]] \
  && message="${message}\n\n${contentname} is available with the **${dlc}** DLC." \
  || /bin/true

  # Check for any notes about this content.
  # This is a rich text field, so... there be dragons.
  # Since Discord somehow can't handle hyperlinks which the WWW has had since 1988
  # we will convert links to "__text__ _(title)_" format, 
  # then create some line breaks, and strip as much other HTML as we can
  local notes=""
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
  fi

  # sometimes an empty save results in "<p><br></p>" so let's deal with that
  [[ "${notes}" == "\n\n\n" ]] && notes=""

  # stash this in a variable we are about to manipulate
  local revised_line="${notes}"

  for word in $(echo "${notes}"); do
    # store any occurence of http[^ ]* into a variable "link"
    local link=$(echo "${word}" \
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

  # Return the message and context (driver on contentname)
  echo "${message}|${driver} on ${contentname}"
}

# Prepare message for session closed rejection
# Arguments: $1 = the log line containing the rejection
# Outputs: message via echo
prepare_session_closed_message() {
  local logline="${1}"
  local message=""

  # Extract driver name from: Driver: John Smith (76561198012345678) tried to join
  local driver=$(echo "${logline}" | sed -n 's/.*Driver: \([^(]*\)(.*/\1/p' | xargs)

  # Initialise the message 
  message="${message_prefix}\n"

  message="${message}\nJoining was blocked for **${driver}** because the current session is closed. \n\nDepending on the server configuration, it _might_ be possible to join when the session ends, e.g. after qualifying but before the race."

  message="${message}\n${message_suffix}"

  # Return the message and context
  echo "${message}|${driver} (session closed)"
}

# Prepare message for no available slots rejection
# Arguments: $1 = the log line containing the rejection
# Outputs: message via echo
prepare_no_slots_message() {
  local logline="${1}"
  local message=""

  # Extract driver name from: Could not connect driver (<name>/<guid>) to car.
  local driver=$(echo "${logline}" | sed -n 's/.*Could not connect driver (\([^/]*\)\/.*/\1/p' | xargs)

  # Initialise the message 
  message="${message_prefix}\n"

  message="${message}\nJoining was blocked (handshake failure) for **${driver}** because the server only accepts assigned drivers at the moment. Check if it's still possible to _register_ for the event, which might permit entry after the next full server restart."

  message="${message}\n${message_suffix}"

  # Return the message and context
  echo "${message}|${driver} (no available slots)"
}

# Prepare message for UDP plugin kick
# Arguments: $1 = the log line containing the kick
# Outputs: message via echo
prepare_plugin_kick_message() {
  local logline="${1}"
  local message=""

  # Extract driver name from: Kicking: CarID: <int>, Name: <name>, GUID: <guid>
  local driver=$(echo "${logline}" | sed -n 's/.*Name: \([^,]*\),.*/\1/p' | xargs)

  # Initialise the message 
  message="${message_prefix}\n"

  message="${message}\nDriver **${driver}** was kicked by a server plugin. Check you have met the requirements and are following all the rules."

  message="${message}\n${message_suffix}"

  # Return the message and context
  echo "${message}|${driver} (plugin kick)"
}

tail -Fn0 "${watchedlog}" 2>&1 | \
while read -r line; do

  message=""

  # Detection: Checksum validation failure
  if [[ $(echo "${line}" | egrep -c 'Kicking.*Checksum failed') -gt 0 ]]; then
    result=$(prepare_checksum_message "${linebefore}" "${watchedlog}")
    message="${result%|*}"
    context="${result#*|}"
    send_webhook "${message}" "${context}"

  # Detection: Session closed rejection
  elif [[ $(echo "${line}" | egrep -c 'tried to join but was rejected as current session is closed') -gt 0 ]]; then
    result=$(prepare_session_closed_message "${line}")
    message="${result%|*}"
    context="${result#*|}"
    send_webhook "${message}" "${context}"

  # Detection: No available slots (assigned drivers only)
  elif [[ $(echo "${line}" | egrep -c 'Could not connect driver.*no available slots') -gt 0 ]]; then
    result=$(prepare_no_slots_message "${line}")
    message="${result%|*}"
    context="${result#*|}"
    send_webhook "${message}" "${context}"

  # Detection: Kicked by UDP plugin (e.g. Real Penalty, KMR, stracker)
  elif [[ $(echo "${line}" | egrep -c 'Kicking:.*reason: UDP Plugin') -gt 0 ]]; then
    result=$(prepare_plugin_kick_message "${line}")
    message="${result%|*}"
    context="${result#*|}"
    send_webhook "${message}" "${context}"
  fi

  linebefore="${line}"
done
