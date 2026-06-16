#!/usr/bin/env bash
# _common.sh
# Shared functions and setup for mock testing scripts

# Change to project root (parent of mocks directory)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
cd "${PROJECT_ROOT}"

# Check required commands
if ! command -v jq &> /dev/null; then
  echo "Error: jq is required but not installed." >&2
  exit 1
fi

if ! command -v curl &> /dev/null; then
  echo "Error: curl is required but not installed." >&2
  exit 1
fi

if ! command -v perl &> /dev/null; then
  echo "Error: perl is required but not installed." >&2
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

wrap_discord_urls() {
  local input="${1}"
  printf '%s' "${input}" | perl -pe 's{(?<!<)\b(https?://[^\s<>()"\x27]+)}{my $url = $1; my $trailing = ""; while ($url =~ s/([.,;:!?]+)\z//) { $trailing = $1 . $trailing; } "<$url>$trailing"}eg'
}

# Validate required environment variables
if [[ -z "${bot_name}" ]]; then
  echo "Error: bot_name is not set in checksum.env." >&2
  exit 1
fi

if [[ -z "${webhookurl}" ]]; then
  echo "Error: webhookurl is not set in .secrets." >&2
  exit 1
fi

# Template directory (default: ./templates)
templates_path="${templates_path:-./templates}"
server_display_name=$(wrap_discord_urls "${server_display_name:-Mock Server}")

# Default values for legacy fallback mode
message_prefix="${message_prefix:-:racing_car: :police_car: :racing_car: :police_car: :racing_car: :police_car:\n}"
message_suffix="${message_suffix:-}"

# Discord Component V2 layout toggle. When enabled, rendered template content is
# wrapped in a Container component instead of sent as traditional message content.
use_component_layouts="${use_component_layouts:-false}"
component_accent_color="${component_accent_color:-16731471}"
component_separator_1_token="%%ACSM_COMPONENT_SEPARATOR_1%%"
component_separator_2_token="%%ACSM_COMPONENT_SEPARATOR_2%%"

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
      # Use bash string replacement (handles multi-line content properly)
      template="${template//"{{ include \"${include_file}\" }}"/${include_content}}"
    else
      echo "Warning: Include file '${include_path}' not found" >&2
      # Remove the include directive to prevent infinite loop
      template="${template//"{{ include \"${include_file}\" }}"/}"
    fi
    ((include_iterations++))
  done
  
  # Strip comments: {{/* ... */}} (supports multi-line)
  # Done after includes so comments in included files are also stripped
  template=$(perl -0777 -pe 's/\{\{\/\*.*?\*\/\}\}//gs' <<< "${template}")
  
  # Build associative array of variables (bash 4+)
  declare -A vars
  local var_list=""
  local var_values=""
  vars["separator-1"]=""
  vars["separator-2"]=""
  if [[ "${use_component_layouts}" == "true" ]]; then
    vars["separator-1"]="${component_separator_1_token}"
    vars["separator-2"]="${component_separator_2_token}"
    var_list="${var_list}separator-1,separator-2,"
    var_values="${var_values}separator-1=${component_separator_1_token}|separator-2=${component_separator_2_token}|"
  fi
  if [[ -n "${server_display_name:-}" ]]; then
    vars["serverName"]="${server_display_name}"
    var_list="${var_list}serverName,"
    local escaped_value=$(echo "${server_display_name}" | sed 's/|/\\|/g')
    var_values="${var_values}serverName=${escaped_value}|"
  fi
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
    # Escape special characters in value for sed (& / \ and newlines)
    value=$(printf '%s' "${value}" | sed -e 's/[&/\]/\\&/g' -e 's/$/\\/' | sed '$ s/\\$//')
    template=$(echo "${template}" | sed "s/{{ \.${key} }}/${value}/g")
  done
  
  # Process conditional blocks using perl
  # Pass variable names and values via environment
  # Key: process innermost blocks first (those without nested {{ if) to handle nesting
  template=$(TMPL_VARS="${var_list}" TMPL_VALUES="${var_values}" perl -0777 -pe '
    my %set_vars = map { $_ => 1 } split /,/, $ENV{"TMPL_VARS"};
    
    # Parse variable values for equality comparisons
    my %var_values;
    for my $pair (split /\|/, $ENV{"TMPL_VALUES"}) {
      if ($pair =~ /^([^=]+)=(.*)$/) {
        $var_values{$1} = $2;
      }
    }
    
    # Helper to evaluate a condition and return replacement
    sub eval_block {
      my ($condition, $block, $set_vars_ref, $var_values_ref) = @_;
      my $replacement = "";
      my $result = 0;
      
      # Parse condition type
      if ($condition =~ /^eq \.(\w+) "([^"]*)"$/) {
        my ($var, $cmp) = ($1, $2);
        $result = (($var_values_ref->{$var} // "") eq $cmp);
      } elsif ($condition =~ /^ne \.(\w+) "([^"]*)"$/) {
        my ($var, $cmp) = ($1, $2);
        $result = (($var_values_ref->{$var} // "") ne $cmp);
      } elsif ($condition =~ /^not \.(\w+)$/) {
        my $var = $1;
        $result = !$set_vars_ref->{$var};
      } elsif ($condition =~ /^\.(\w+)$/) {
        my $var = $1;
        $result = $set_vars_ref->{$var};
      }
      
      # Handle else clause
      if ($block =~ /^(.*?)\{\{ else \}\}(.*)$/s) {
        $replacement = $result ? $1 : $2;
      } else {
        $replacement = $result ? $block : "";
      }
      return $replacement;
    }
    
    # Process innermost blocks first (those without nested {{ if inside)
    # Repeat until no more matches - this handles arbitrary nesting depth
    my $changed = 1;
    while ($changed) {
      $changed = 0;
      
      # Match {{ if CONDITION }}BLOCK{{ end }} where BLOCK contains no {{ if
      if (s/\{\{ if ((?:eq |ne |not )?\.(\w+)(?: "[^"]*")?) \}\}((?:(?!\{\{ if )(?!\{\{ end \}\}).)*?)\{\{ end \}\}/
          eval_block($1, $3, \%set_vars, \%var_values)/es) {
        $changed = 1;
      }
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

resolve_component_accent_color() {
  local color="${component_accent_color:-16731471}"
  local numeric

  if [[ "${color,,}" == "random" ]]; then
    random_component_accent_color
    return
  fi

  if [[ "${color}" =~ ^0[xX][0-9a-fA-F]{1,6}$ ]]; then
    numeric=$((color))
  elif [[ "${color}" =~ ^[0-9]+$ ]]; then
    numeric=$((10#${color}))
  else
    echo "16731471"
    return
  fi

  if (( numeric >= 0 && numeric <= 16777215 )); then
    echo "${numeric}"
  else
    echo "16731471"
  fi
}

random_component_accent_color() {
  local red
  local green
  local blue

  while true; do
    red=$((RANDOM % 256))
    green=$((RANDOM % 256))
    blue=$((RANDOM % 256))

    if ! (( red < 0x4f && green < 0x4f && blue < 0x4f )); then
      echo $(((red << 16) + (green << 8) + blue))
      return
    fi
  done
}

append_query_param() {
  local url="${1}"
  local param="${2}"

  if [[ "${url}" == *\?* ]]; then
    echo "${url}&${param}"
  else
    echo "${url}?${param}"
  fi
}

build_component_payload() {
  local message="${1}"
  local accent_color
  accent_color=$(resolve_component_accent_color)

  jq -n \
    --arg username "${bot_name}" \
    --arg body "${message}" \
    --arg separator_1 "${component_separator_1_token}" \
    --arg separator_2 "${component_separator_2_token}" \
    --argjson accent_color "${accent_color}" \
    '
    def text_component($content):
      if (($content | gsub("^[[:space:]]+|[[:space:]]+$"; "") | length) > 0)
      then [{type: 10, content: $content}]
      else []
      end;

    def component_parts($text):
      ($text | index($separator_1)) as $index_1
      | ($text | index($separator_2)) as $index_2
      | if $index_1 == null and $index_2 == null then
          text_component($text)
        elif $index_2 == null or ($index_1 != null and $index_1 < $index_2) then
          text_component($text[0:$index_1])
          + [{type: 14, divider: true, spacing: 1}]
          + component_parts($text[($index_1 + ($separator_1 | length)):])
        else
          text_component($text[0:$index_2])
          + [{type: 14, divider: true, spacing: 2}]
          + component_parts($text[($index_2 + ($separator_2 | length)):])
        end;

    {
      username: $username,
      flags: 32768,
      components: [
        {
          type: 17,
          accent_color: $accent_color,
          components: (
            component_parts($body)
            | if length > 0 then . else [{type: 10, content: "\u200b"}] end
          )
        }
      ]
    }'
}

# Parse HTML notes into Discord-friendly plain text
# Mirrors the pipeline in checker.sh's prepare_checksum_message()
# Arguments: $1 = raw HTML notes string
# Outputs: cleaned plain text via echo
parse_notes() {
  local raw="${1}"
  local notes
  notes=$(echo "${raw}" \
    | tr '\r\n' ' ' \
    | sed 's|<a href="\([^"]*\)"[^>]*>\([^<]*\)</a>|__\2__ _(@LT@\1@GT@)_|g' \
    | sed "s|\"|'|g" \
    | sed 's|<br>|@NL@|g' \
    | sed 's|<p>|@NL@|g' \
    | sed 's|</p>|@NL@|g' \
    | sed 's|<ul>|@NL@|g' \
    | sed 's|<li>|• |g' \
    | sed 's|</li>|@NL@|g' \
    | sed 's|<[^>]*>||g' \
    | sed 's|&nbsp;| |g' \
    | sed 's|&gt;|>|g' \
    | sed 's|&lt;|<|g' \
    | sed "s|&quot;|\"|g" \
    | sed 's|&amp;|\&|g' \
    | sed 's|@LT@|<|g' \
    | sed 's|@GT@|>|g' )

  # De-duplicate self-referencing links: __URL__ _(<URL>)_ → <URL>
  notes=$(echo "${notes}" | sed -E 's|__([^_]+)__ _\(<\1>\)_|<\1>|g')

  # Convert @NL@ placeholders to real newlines, trim leading/trailing, compress runs
  notes=$(echo "${notes}" | sed 's|@NL@|\n|g' \
    | sed '/./,$!d' \
    | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}' \
    | cat -s)

  # Wrap remaining bare URLs to suppress Discord link previews.
  notes=$(wrap_discord_urls "${notes}")

  # Strip notes that are effectively empty
  local notes_stripped=$(echo "${notes}" | xargs)
  [[ -z "${notes_stripped}" ]] && notes=""

  echo "${notes}"
}

# Send a message to the Discord webhook
# Arguments: $1 = message, $2 = context for error logging
send_webhook() {
  local message="${1}"
  local context="${2}"

  local payload
  local webhook_target="${webhookurl}"
  if [[ "${use_component_layouts}" == "true" ]]; then
    payload=$(build_component_payload "${message}")
    webhook_target=$(append_query_param "${webhook_target}" "with_components=true")
  else
    # Escape message content for JSON
    local escaped_message=$(escape_for_json "${message}")
    local escaped_bot_name=$(escape_for_json "${bot_name}")

    payload='{"username": "'"${escaped_bot_name}"'", "content": "'"${escaped_message}"'"}'
  fi

  if [[ -n "${message}" ]]; then
    echo "=== Sending webhook for: ${context} ===" >&2
    echo "Payload preview:" >&2
    echo "${message}" >&2
    echo "===" >&2
    if ! curl -sf -H "Content-Type: application/json" -d "${payload}" "${webhook_target}"; then
      echo "Warning: Failed to send webhook notification for ${context}" >&2
      return 1
    fi
    echo "Success: Webhook sent for ${context}" >&2
  fi
}

# Dry-run mode: show what would be sent without actually sending
# Arguments: $1 = message, $2 = context for logging
dry_run_webhook() {
  local message="${1}"
  local context="${2}"
  
  echo "=== DRY RUN: ${context} ===" 
  if [[ "${use_component_layouts}" == "true" ]]; then
    echo "Would send the following Component V2 payload:"
    echo "---"
    build_component_payload "${message}"
    echo "---"
  else
    echo "Would send the following message:"
    echo "---"
    echo -e "${message}"
    echo "---"
  fi
  echo ""
}
