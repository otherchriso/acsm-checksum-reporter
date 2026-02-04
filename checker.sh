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

# message_prefix and message_suffix are only required if templates are not available
templates_path="${templates_path:-./templates}"
if [[ ! -d "${templates_path}" ]]; then
  if [[ -z "${message_prefix}" ]]; then
    echo "Error: message_prefix is not set in checksum.env (required when templates not available)." >&2
    exit 1
  fi

  if [[ -z "${message_suffix}" ]]; then
    echo "Error: message_suffix is not set in checksum.env (required when templates not available)." >&2
    exit 1
  fi
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

# Template directory (default: ./templates)
templates_path="${templates_path:-./templates}"

# Validate template syntax
# Arguments: $1 = template file path
# Returns: 0 if valid, 1 if errors found (errors printed to stderr)
validate_template_syntax() {
  local template_file="${1}"
  local errors=0
  
  if [[ ! -f "${template_file}" ]]; then
    echo "Error: Template file '${template_file}' not found" >&2
    return 1
  fi
  
  local content=$(cat "${template_file}")
  
  # Check for balanced {{ and }}
  local open_count=$(echo "${content}" | grep -o '{{' | wc -l)
  local close_count=$(echo "${content}" | grep -o '}}' | wc -l)
  if [[ "${open_count}" -ne "${close_count}" ]]; then
    echo "Error: Unbalanced {{ }} in ${template_file} (${open_count} open, ${close_count} close)" >&2
    errors=1
  fi
  
  # Check for unclosed if blocks (count {{ if vs {{ end }})
  local if_count=$(echo "${content}" | grep -oE '\{\{ if ' | wc -l)
  local end_count=$(echo "${content}" | grep -oE '\{\{ end \}\}' | wc -l)
  if [[ "${if_count}" -ne "${end_count}" ]]; then
    echo "Error: Mismatched if/end blocks in ${template_file} (${if_count} if, ${end_count} end)" >&2
    errors=1
  fi
  
  # Check for include directives pointing to missing files
  local includes=$(echo "${content}" | grep -oE '\{\{ include "[^"]*" \}\}' | sed 's/{{ include "//g' | sed 's/" }}//g')
  for inc in ${includes}; do
    if [[ ! -f "${templates_path}/${inc}" ]]; then
      echo "Error: Included template '${inc}' not found in ${template_file}" >&2
      errors=1
    fi
  done
  
  return ${errors}
}

# Validate all templates on startup
# Returns: 0 if all valid, 1 if any errors (continues checking all templates)
validate_templates() {
  local errors=0
  
  if [[ ! -d "${templates_path}" ]]; then
    # Templates directory doesn't exist - using legacy mode
    return 0
  fi
  
  for tmpl in "${templates_path}"/*.tmpl; do
    if [[ -f "${tmpl}" ]]; then
      if ! validate_template_syntax "${tmpl}"; then
        errors=1
      fi
    fi
  done
  
  if [[ "${errors}" -ne 0 ]]; then
    echo "Warning: Template validation found errors. Messages may not render correctly." >&2
  fi
  
  return ${errors}
}

# Validate templates at startup (non-fatal - just warns)
validate_templates

# Resolve the shared store path from ACSM config
# Returns: path to shared store directory (without trailing slash)
resolve_shared_store_path() {
  local config_path="${acsm_config_path:-}"
  local shared_path=""
  
  if [[ -n "${config_path}" && -f "${config_path}" ]]; then
    # Try to extract shared_data_path from config.yml
    shared_path=$(grep -E '^\s*shared_data_path:' "${config_path}" 2>/dev/null | awk '{print $2}' | tr -d '"' | tr -d "'")
  fi
  
  # If empty or not found, use default relative to config directory
  if [[ -z "${shared_path}" ]]; then
    if [[ -n "${config_path}" ]]; then
      local config_dir=$(dirname "${config_path}")
      shared_path="${config_dir}/shared_store.json"
    else
      # Fallback: try common locations
      shared_path=""
    fi
  fi
  
  echo "${shared_path}"
}

# Look up expected checksum for a failed file
# Arguments: $1 = failed file path, $2 = hintfile (content metadata JSON)
# Outputs: checksum string (or empty if not found)
lookup_expected_checksum() {
  local failed_file="${1}"
  local hintfile="${2}"
  local checksum=""
  
  # Content checksums (cars/tracks) - look in metadata .checksums array
  if [[ "${failed_file}" =~ ^content/(cars|tracks)/ && -f "${hintfile}" ]]; then
    checksum=$(jq -r --arg fp "${failed_file}" \
      '.checksums[]? | select(.filepath == $fp) | .checksum // empty' \
      "${hintfile}" 2>/dev/null)
  fi
  
  echo "${checksum}"
}

# Look up custom checksum entry (for non-content files like apps, dlls)
# Arguments: $1 = failed file path
# Outputs: "name|checksum" (pipe-separated) or empty if not found
lookup_custom_checksum() {
  local failed_file="${1}"
  local result=""
  
  local shared_path=$(resolve_shared_store_path)
  local custom_checksums_file="${shared_path}/custom_checksums.json"
  
  if [[ -n "${shared_path}" && -f "${custom_checksums_file}" ]]; then
    # Extract both name and checksum for the matching entry
    result=$(jq -r --arg fp "${failed_file}" \
      '.entries[]? | select(.filepath == $fp) | "\(.name // "")|\(.checksum // "")"' \
      "${custom_checksums_file}" 2>/dev/null)
  fi
  
  echo "${result}"
}

# Render a template with variable substitution and conditional blocks
# Arguments: $1 = template name (without .tmpl extension)
#            Remaining args: key=value pairs for variables
# Outputs: rendered template via echo
render_template() {
  local template_name="${1}"
  shift
  local template_file="${templates_path}/${template_name}.tmpl"
  
  # Check if template exists, fall back to legacy behaviour if not
  if [[ ! -f "${template_file}" ]]; then
    echo "Warning: Template '${template_file}' not found, using legacy format" >&2
    return 1
  fi
  
  local template=$(cat "${template_file}")
  
  # Process {{ include "filename.tmpl" }} directives
  # Use a loop to handle nested includes (max 10 iterations to prevent infinite loops)
  local include_iterations=0
  while [[ "${template}" =~ \{\{\ include\ \"([^\"]+)\"\ \}\} && ${include_iterations} -lt 10 ]]; do
    local include_match="${BASH_REMATCH[0]}"
    local include_file="${BASH_REMATCH[1]}"
    local include_path="${templates_path}/${include_file}"
    
    if [[ -f "${include_path}" ]]; then
      local include_content=$(cat "${include_path}")
      # Escape special characters for sed replacement
      include_content=$(echo "${include_content}" | sed 's/[&/\]/\\&/g')
      template=$(echo "${template}" | sed "s|{{ include \"${include_file}\" }}|${include_content}|g")
    else
      echo "Warning: Include file '${include_path}' not found" >&2
      # Remove the include directive to prevent infinite loop
      template=$(echo "${template}" | sed "s|{{ include \"${include_file}\" }}||g")
    fi
    ((include_iterations++))
  done
  
  # Build associative array of variables (bash 4+)
  declare -A vars
  local var_list=""
  local var_values=""
  for arg in "$@"; do
    local key="${arg%%=*}"
    local value="${arg#*=}"
    vars["${key}"]="${value}"
    # Track non-empty variables for conditional processing
    if [[ -n "${value}" ]]; then
      var_list="${var_list}${key},"
      # Build key=value pairs for equality checks (escape | in values)
      local escaped_value=$(echo "${value}" | sed 's/|/\\|/g')
      var_values="${var_values}${key}=${escaped_value}|"
    fi
  done
  
  # Variable substitution: {{ .varName }} -> value
  for key in "${!vars[@]}"; do
    local value="${vars[$key]}"
    # Escape special characters in value for sed
    value=$(echo "${value}" | sed 's/[&/\]/\\&/g')
    template=$(echo "${template}" | sed "s/{{ \.${key} }}/${value}/g")
  done
  
  # Process conditional blocks using perl
  # Pass variable names and values via environment
  template=$(TMPL_VARS="${var_list}" TMPL_VALUES="${var_values}" perl -0777 -pe '
    my %set_vars = map { $_ => 1 } split /,/, $ENV{"TMPL_VARS"};
    
    # Parse variable values for equality comparisons
    my %var_values;
    for my $pair (split /\|/, $ENV{"TMPL_VALUES"}) {
      if ($pair =~ /^([^=]+)=(.*)$/) {
        $var_values{$1} = $2;
      }
    }
    
    # Process {{ if eq .var "value" }}...{{ else }}...{{ end }} blocks
    while (/\{\{ if eq \.(\w+) "([^"]*)" \}\}(.*?)\{\{ end \}\}/s) {
      my $var = $1;
      my $compare_val = $2;
      my $block = $3;
      my $replacement = "";
      my $actual_val = $var_values{$var} // "";
      
      if ($block =~ /^(.*?)\{\{ else \}\}(.*)$/s) {
        my ($if_content, $else_content) = ($1, $2);
        $replacement = ($actual_val eq $compare_val) ? $if_content : $else_content;
      } else {
        $replacement = ($actual_val eq $compare_val) ? $block : "";
      }
      s/\{\{ if eq \.$var "[^"]*" \}\}.*?\{\{ end \}\}/$replacement/s;
    }
    
    # Process {{ if ne .var "value" }}...{{ else }}...{{ end }} blocks
    while (/\{\{ if ne \.(\w+) "([^"]*)" \}\}(.*?)\{\{ end \}\}/s) {
      my $var = $1;
      my $compare_val = $2;
      my $block = $3;
      my $replacement = "";
      my $actual_val = $var_values{$var} // "";
      
      if ($block =~ /^(.*?)\{\{ else \}\}(.*)$/s) {
        my ($if_content, $else_content) = ($1, $2);
        $replacement = ($actual_val ne $compare_val) ? $if_content : $else_content;
      } else {
        $replacement = ($actual_val ne $compare_val) ? $block : "";
      }
      s/\{\{ if ne \.$var "[^"]*" \}\}.*?\{\{ end \}\}/$replacement/s;
    }
    
    # Process {{ if not .var }}...{{ else }}...{{ end }} blocks
    while (/\{\{ if not \.(\w+) \}\}(.*?)\{\{ end \}\}/s) {
      my $var = $1;
      my $block = $2;
      my $replacement = "";
      
      if ($block =~ /^(.*?)\{\{ else \}\}(.*)$/s) {
        my ($if_content, $else_content) = ($1, $2);
        $replacement = (!$set_vars{$var}) ? $if_content : $else_content;
      } else {
        $replacement = (!$set_vars{$var}) ? $block : "";
      }
      s/\{\{ if not \.$var \}\}.*?\{\{ end \}\}/$replacement/s;
    }
    
    # Process {{ if .var }}...{{ else }}...{{ end }} blocks
    while (/\{\{ if \.(\w+) \}\}(.*?)\{\{ end \}\}/s) {
      my $var = $1;
      my $block = $2;
      my $replacement = "";
      
      if ($block =~ /^(.*?)\{\{ else \}\}(.*)$/s) {
        my ($if_content, $else_content) = ($1, $2);
        $replacement = ($set_vars{$var}) ? $if_content : $else_content;
      } else {
        $replacement = ($set_vars{$var}) ? $block : "";
      }
      s/\{\{ if \.$var \}\}.*?\{\{ end \}\}/$replacement/s;
    }
  ' <<< "${template}")
  
  # Clean up any remaining unsubstituted variables (replace with empty)
  template=$(echo "${template}" | sed 's/{{ \.[a-zA-Z]*}}//g')
  
  # Clean up multiple consecutive blank lines
  template=$(echo "${template}" | cat -s)
  
  echo "${template}"
}

# Escape a string for safe embedding in JSON
# Arguments: $1 = string to escape
# Outputs: escaped string via echo
escape_for_json() {
  local input="${1}"
  # Use jq to properly escape the string for JSON
  # The -Rs flags: -R reads raw input, -s slurps into single string
  # Output is a valid JSON string (with quotes), we strip the quotes
  local escaped=$(echo -n "${input}" | jq -Rs '.' | sed 's/^"//;s/"$//')
  echo "${escaped}"
}

# Send a message to the Discord webhook
# Arguments: $1 = message, $2 = context for error logging
send_webhook() {
  local message="${1}"
  local context="${2}"
  
  # Escape message content for JSON
  local escaped_message=$(escape_for_json "${message}")
  local escaped_bot_name=$(escape_for_json "${bot_name}")
  
  local payload='{"username": "'"${escaped_bot_name}"'", "content": "'"${escaped_message}"'"}'

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

  # Extract the failed file path (e.g. "content/cars/mod_name/data.acd")
  local failedfile=$(echo "${details}" \
                | awk '{print $1}' \
                | sed 's/^content/content/')

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
  # Clean up null/empty dlc
  [[ "${dlc}" == "null" || ${#dlc} -lt 5 ]] && dlc=""

  # Check for any notes about this content.
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
  [[ "${notes}" == "\n\n\n" || "${notes}" == "null" ]] && notes=""

  # Clean up egregious self-referencing links in notes
  local revised_line="${notes}"
  for word in $(echo "${notes}"); do
    local link=$(echo "${word}" \
             | egrep -o 'http.*' \
             | sed 's|\\n$||' \
             | sed 's|__$||')
    revised_line=$(echo "${revised_line}" \
                   | sed "s|__${link}__ _.<${link}>._|<${link}>|g")
  done
  notes="${revised_line}"

  # Look up expected checksum and custom name
  local expectedchecksum=""
  local customname=""
  
  if [[ -n "${failedfile}" ]]; then
    # Try content metadata first
    expectedchecksum=$(lookup_expected_checksum "${failedfile}" "${hintfile}")
    
    # If not in content metadata, check custom checksums
    if [[ -z "${expectedchecksum}" ]]; then
      local custom_result=$(lookup_custom_checksum "${failedfile}")
      if [[ -n "${custom_result}" ]]; then
        customname="${custom_result%|*}"
        expectedchecksum="${custom_result#*|}"
      fi
    fi
  fi

  # Try to render from template
  message=$(render_template "checksum_failure" \
    "driver=${driver}" \
    "contentType=${contenttype}" \
    "contentName=${contentname}" \
    "failedFile=${failedfile}" \
    "expectedChecksum=${expectedchecksum}" \
    "customName=${customname}" \
    "downloadURL=${downloadurl}" \
    "dlcPack=${dlc}" \
    "notes=${notes}")
  
  # Fall back to legacy format if template rendering failed
  if [[ $? -ne 0 || -z "${message}" ]]; then
    message="${message_prefix}\n"
    message="${message}\nChecksum failed for **${driver}** on ${contenttype} **${contentname}**"
    [[ -n "${dlc}" ]] && message="${message}\n\n${contentname} is available with the **${dlc}** DLC."
    [[ ${#downloadurl} -gt 5 ]] \
    && message="${message}\n\n**Content download:**\n<${downloadurl}>\n" \
    || message="${message}\n\nWe don't have a download link for that. If the content is stock or DLC, make sure you have installed it, and verify your game files in Steam.\n"
    [[ ${#notes} -gt 3 ]] && message="${message}\n**Important notes:**\n${notes}"
    message="${message}\n${message_suffix}"
  fi

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

  # Try to render from template
  message=$(render_template "session_closed" "driver=${driver}")
  
  # Fall back to legacy format if template rendering failed
  if [[ $? -ne 0 || -z "${message}" ]]; then
    message="${message_prefix}\n"
    message="${message}\nJoining was blocked for **${driver}** because the current session is closed. \n\nDepending on the server configuration, it _might_ be possible to join when the session ends, e.g. after qualifying but before the race."
    message="${message}\n${message_suffix}"
  fi

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

  # Try to render from template
  message=$(render_template "no_slots" "driver=${driver}")
  
  # Fall back to legacy format if template rendering failed
  if [[ $? -ne 0 || -z "${message}" ]]; then
    message="${message_prefix}\n"
    message="${message}\nJoining was blocked (handshake failure) for **${driver}** because the server only accepts assigned drivers at the moment. Check if it's still possible to _register_ for the event, which might permit entry after the next full server restart."
    message="${message}\n${message_suffix}"
  fi

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

  # Try to render from template
  message=$(render_template "plugin_kick" "driver=${driver}")
  
  # Fall back to legacy format if template rendering failed
  if [[ $? -ne 0 || -z "${message}" ]]; then
    message="${message_prefix}\n"
    message="${message}\nDriver **${driver}** was kicked by a server plugin. Check you have met the requirements and are following all the rules."
    message="${message}\n${message_suffix}"
  fi

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
