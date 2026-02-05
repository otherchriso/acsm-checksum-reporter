#!/usr/bin/env bash
# mock_checksum_failure.sh
# Mock script to test checksum failure template rendering and webhook delivery

source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

# Usage info
usage() {
  echo "Usage: $0 [--dry-run] [--scenario <name>]"
  echo ""
  echo "Scenarios:"
  echo "  minimal     - Only driver, contentType, contentName (no optional fields)"
  echo "  with-url    - Includes download URL"
  echo "  with-dlc    - Includes DLC pack info"
  echo "  with-oc     - Original game content (no DLC)"
  echo "  with-notes  - Includes notes field"
  echo "  custom-mod  - Custom mod with checksum info"
  echo "  full        - All fields populated (default)"
  echo ""
  echo "Options:"
  echo "  --dry-run   Show rendered message without sending to webhook"
  exit 1
}

# Parse arguments
DRY_RUN=false
SCENARIO="full"

while [[ $# -gt 0 ]]; do
  case "${1}" in
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --scenario)
      SCENARIO="${2}"
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

# Mock data for different scenarios
case "${SCENARIO}" in
  minimal)
    driver="TV Car"
    contentType="track"
    contentName="rj_lemans_1967"
    failedFile=""
    expectedChecksum=""
    customName=""
    downloadURL=""
    dlcPack=""
    isOriginalContent=""
    notes=""
    ;;
  with-url)
    driver="John Smith"
    contentType="car"
    contentName="ks_ferrari_488_gt3"
    failedFile="content/cars/ks_ferrari_488_gt3/data.acd"
    expectedChecksum=""
    customName=""
    downloadURL="https://www.racedepartment.com/downloads/example-mod.12345/"
    dlcPack=""
    isOriginalContent=""
    notes=""
    ;;
  with-dlc)
    driver="Max Verstappen"
    contentType="car"
    contentName="ks_porsche_911_gt3_r_2016"
    failedFile="content/cars/ks_porsche_911_gt3_r_2016/data.acd"
    expectedChecksum=""
    customName=""
    downloadURL=""
    dlcPack="Porsche Pack I"
    isOriginalContent=""
    notes=""
    ;;
  with-oc)
    driver="Charles Leclerc"
    contentType="car"
    contentName="lotus_exige_v6_cup"
    failedFile="content/cars/lotus_exige_v6_cup/data.acd"
    expectedChecksum=""
    customName=""
    downloadURL=""
    dlcPack=""
    isOriginalContent="true"
    notes=""
    ;;
  with-notes)
    driver="Lewis Hamilton"
    contentType="track"
    contentName="spa"
    failedFile="content/tracks/spa/data/surfaces.ini"
    expectedChecksum=""
    customName=""
    downloadURL="https://example.com/spa-mod"
    dlcPack=""
    isOriginalContent=""
    notes="This is a custom version of Spa with updated surfaces.\nMake sure to download version 2.1 or later."
    ;;
  custom-mod)
    driver="Lando Norris"
    contentType=""
    contentName=""
    failedFile="apps/python/sol_weather/sol_weather.py"
    expectedChecksum="abc123def456"
    customName="Sol"
    downloadURL="https://www.racedepartment.com/downloads/sol.24914/"
    dlcPack=""
    isOriginalContent=""
    notes=""
    ;;
  full)
    driver="TV Car"
    contentType="car"
    contentName="ks_ferrari_sf70h"
    failedFile="content/cars/ks_ferrari_sf70h/data.acd"
    expectedChecksum="deadbeef1234567890"
    customName="Ferrari SF70H Server Pack"
    downloadURL="https://www.racedepartment.com/downloads/ferrari-sf70h.54321/"
    dlcPack="Ferrari 70th Anniversary"
    isOriginalContent=""
    notes="Updated physics for competitive racing.\nVersion must match server exactly."
    ;;
  *)
    echo "Unknown scenario: ${SCENARIO}"
    usage
    ;;
esac

echo "Testing checksum_failure template with scenario: ${SCENARIO}"
echo ""

# Render the template
message=$(render_template "checksum_failure" \
  "driver=${driver}" \
  "contentType=${contentType}" \
  "contentName=${contentName}" \
  "failedFile=${failedFile}" \
  "expectedChecksum=${expectedChecksum}" \
  "customName=${customName}" \
  "downloadURL=${downloadURL}" \
  "dlcPack=${dlcPack}" \
  "isOriginalContent=${isOriginalContent}" \
  "notes=${notes}")

render_status=$?
context="${driver} on ${contentName}"

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
