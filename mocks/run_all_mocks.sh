#!/usr/bin/env bash
# run_all_mocks.sh
# Convenience script to run all mock tests

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Usage info
usage() {
  echo "Usage: $0 [--dry-run] [--live]"
  echo ""
  echo "Runs all mock scripts to test template rendering."
  echo ""
  echo "Options:"
  echo "  --dry-run   Show rendered messages without sending (default)"
  echo "  --live      Actually send to Discord webhook"
  echo ""
  exit 1
}

# Parse arguments
MODE="--dry-run"

while [[ $# -gt 0 ]]; do
  case "${1}" in
    --dry-run)
      MODE="--dry-run"
      shift
      ;;
    --live)
      MODE=""
      shift
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

echo "========================================"
echo "Running all mock tests"
[[ -n "${MODE}" ]] && echo "Mode: DRY RUN (no webhooks sent)"
[[ -z "${MODE}" ]] && echo "Mode: LIVE (sending to webhook)"
echo "========================================"
echo ""

# Run each mock
echo ">>> Plugin Kick"
"${SCRIPT_DIR}/mock_plugin_kick.sh" ${MODE}
[[ -z "${MODE}" ]] && sleep 1
echo ""

echo ">>> No Available Slots"
"${SCRIPT_DIR}/mock_no_slots.sh" ${MODE}
[[ -z "${MODE}" ]] && sleep 1
echo ""

echo ">>> Session Closed"
"${SCRIPT_DIR}/mock_session_closed.sh" ${MODE}
[[ -z "${MODE}" ]] && sleep 1
echo ""

echo ">>> Checksum Failure (minimal)"
"${SCRIPT_DIR}/mock_checksum_failure.sh" ${MODE} --scenario minimal
[[ -z "${MODE}" ]] && sleep 1
echo ""

echo ">>> Checksum Failure (with-url)"
"${SCRIPT_DIR}/mock_checksum_failure.sh" ${MODE} --scenario with-url
[[ -z "${MODE}" ]] && sleep 1
echo ""

echo ">>> Checksum Failure (with-dlc)" 
"${SCRIPT_DIR}/mock_checksum_failure.sh" ${MODE} --scenario with-dlc
[[ -z "${MODE}" ]] && sleep 1
echo ""

echo ">>> Checksum Failure (custom-mod)"
"${SCRIPT_DIR}/mock_checksum_failure.sh" ${MODE} --scenario custom-mod
[[ -z "${MODE}" ]] && sleep 1
echo ""

echo ">>> Checksum Failure (full)"
"${SCRIPT_DIR}/mock_checksum_failure.sh" ${MODE} --scenario full
echo ""

echo "========================================"
echo "All mock tests completed"
echo "========================================"
