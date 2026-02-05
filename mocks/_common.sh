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

# Default values for legacy fallback mode
message_prefix="${message_prefix:-:racing_car: :police_car: :racing_car: :police_car: :racing_car: :police_car:\n}"
message_suffix="${message_suffix:-}"

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
    echo "=== Sending webhook for: ${context} ===" >&2
    echo "Payload preview:" >&2
    echo "${message}" >&2
    echo "===" >&2
    if ! curl -sf -H "Content-Type: application/json" -d "${payload}" "${webhookurl}"; then
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
  echo "Would send the following message:"
  echo "---"
  echo -e "${message}"
  echo "---"
  echo ""
}
