#!/usr/bin/env bash
# mock_session_closed.sh
# Mock script to test session closed template rendering and webhook delivery

source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

# Usage info
usage() {
  echo "Usage: $0 [--dry-run] [--driver <name>]"
  echo ""
  echo "Options:"
  echo "  --dry-run         Show rendered message without sending to webhook"
  echo "  --driver <name>   Driver name to use (default: 'John Smith')"
  exit 1
}

# Parse arguments
DRY_RUN=false
driver="John Smith"

while [[ $# -gt 0 ]]; do
  case "${1}" in
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --driver)
      driver="${2}"
      shift 2
      ;;
    --help|-h)
      usage
      ;;
    *)
      echo "Unknown option: ${1}"
      usage
      ;;
  esac
done

echo "Testing session_closed template with driver: ${driver}"
echo ""

# Render the template
message=$(render_template "session_closed" "driver=${driver}")

render_status=$?
context="${driver} (session closed)"

if [[ ${render_status} -ne 0 || -z "${message}" ]]; then
  echo "ERROR: Template rendering failed!" >&2
  exit 1
fi

# Send or dry-run
if [[ "${DRY_RUN}" == "true" ]]; then
  dry_run_webhook "${message}" "${context}"
else
  send_webhook "${message}" "${context}"
fi
