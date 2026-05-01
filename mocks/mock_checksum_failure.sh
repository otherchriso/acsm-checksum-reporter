#!/usr/bin/env bash
# mock_checksum_failure.sh
# Mock script to test checksum failure template rendering and webhook delivery

source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

# Usage info
usage() {
  echo "Usage: $0 [--dry-run] [--scenario <name>]"
  echo ""
  echo "Scenarios:"
  echo "  minimal       - Only driver, contentType, contentName (no optional fields)"
  echo "  with-url      - Includes download URL"
  echo "  with-dlc      - Includes DLC pack info"
  echo "  with-oc       - Original game content (no DLC)"
  echo "  with-notes    - Includes notes field"
  echo "  notes-html-link      - Notes with a named HTML anchor"
  echo "  notes-self-link      - Notes with an HTML anchor whose text is the URL"
  echo "  notes-bare-url       - Notes with a bare URL in text"
  echo "  notes-multiple-urls  - Notes with multiple bare URLs in separate paragraphs"
  echo "  required-file - Non-car/track file (e.g. app or plugin)"
  echo "  custom-mod    - Custom mod with checksum info and known name"
  echo "  full          - All fields populated (default)"
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
    driver="Driver Zero"
    contentType="track"
    contentName="rj_lemans_1967"
    requiredFile=""
    failedFile=""
    expectedChecksum=""
    customName=""
    downloadURL=""
    dlcPack=""
    isOriginalContent=""
    notes=""
    ;;
  with-url)
    driver="Driver Zero"
    contentType="car"
    contentName="ks_ferrari_488_gt3"
    requiredFile=""
    failedFile="content/cars/ks_ferrari_488_gt3/data.acd"
    expectedChecksum=""
    customName=""
    downloadURL="https://github.com/otherchriso/acsm-checksum-reporter"
    dlcPack=""
    isOriginalContent=""
    notes=""
    ;;
  with-dlc)
    driver="Driver Zero"
    contentType="car"
    contentName="ks_porsche_911_gt3_r_2016"
    requiredFile=""
    failedFile="content/cars/ks_porsche_911_gt3_r_2016/data.acd"
    expectedChecksum=""
    customName=""
    downloadURL=""
    dlcPack="Porsche Pack I"
    isOriginalContent=""
    notes=""
    ;;
  with-oc)
    driver="Driver Zero"
    contentType="car"
    contentName="lotus_exige_v6_cup"
    requiredFile=""
    failedFile="content/cars/lotus_exige_v6_cup/data.acd"
    expectedChecksum=""
    customName=""
    downloadURL=""
    dlcPack=""
    isOriginalContent="true"
    notes=""
    ;;
  with-notes)
    driver="Driver Zero"
    contentType="track"
    contentName="spa"
    requiredFile=""
    failedFile="content/tracks/spa/data/surfaces.ini"
    expectedChecksum=""
    customName=""
    downloadURL="https://github.com/otherchriso/acsm-checksum-reporter"
    dlcPack=""
    isOriginalContent=""
    notes='<p>This is a custom version of Spa with updated surfaces.</p><p>Make sure to download version 2.1 or later.</p>'
    ;;
  notes-html-link)
    driver="Vincertje"
    contentType="car"
    contentName="wsc_legends_porsche_906"
    requiredFile=""
    failedFile="content/cars/wsc_legends_porsche_906/data.acd"
    expectedChecksum=""
    customName=""
    downloadURL="https://github.com/otherchriso/acsm-checksum-reporter"
    dlcPack=""
    isOriginalContent=""
    notes='<p>This is version 1.3 of the car, published on January 13 2026. See <a href="https://github.com/otherchriso/acsm-checksum-reporter">the THR website</a> for info on properly obtaining and installing the entire pack.</p>'
    ;;
  notes-self-link)
    driver="Driver Zero"
    contentType="car"
    contentName="rss_gt_pack"
    requiredFile=""
    failedFile="content/cars/rss_gt_pack/data.acd"
    expectedChecksum=""
    customName=""
    downloadURL=""
    dlcPack=""
    isOriginalContent=""
    notes='<p>Replacement badges and names for the real world cars can be found at <a href="https://github.com/otherchriso/acsm-checksum-reporter" target="_blank">https://github.com/otherchriso/acsm-checksum-reporter</a></p>'
    ;;
  notes-bare-url)
    driver="Driver Zero"
    contentType="car"
    contentName="porsche_911_singer"
    requiredFile=""
    failedFile="content/cars/porsche_911_singer/data.acd"
    expectedChecksum=""
    customName=""
    downloadURL=""
    dlcPack=""
    isOriginalContent=""
    notes='<p>CSP v0.2.8 or newer required. The car version installed here is currently v1.3.3 per&nbsp;https://github.com/otherchriso/acsm-checksum-reporter</p>'
    ;;
  notes-multiple-urls)
    driver="Falling Falcon"
    contentType="track"
    contentName="ablz_targaflorio73"
    requiredFile=""
    failedFile="content/tracks/ablz_targaflorio73/ablz_targaflorio73.kn5"
    expectedChecksum="0ed5b35862b0cdd38facb271ad3d7c0b"
    customName=""
    downloadURL=""
    dlcPack=""
    isOriginalContent=""
    notes='<p>LINKS</p><p>Track Targa Florio v0.2.05 from November 2024: https://github.com/otherchriso/acsm-checksum-reporter</p><p>Track practice full layout extension with timing fix (INSTALL MANUALLY): https://github.com/otherchriso/acsm-checksum-reporter</p>'
    ;;
  required-file)
    driver="Driver Zero"
    contentType=""
    contentName=""
    requiredFile="sol_weather.py"
    failedFile="apps/python/sol_weather/sol_weather.py"
    expectedChecksum=""
    customName=""
    downloadURL=""
    dlcPack=""
    isOriginalContent=""
    notes=""
    ;;
  custom-mod)
    driver="Driver Zero"
    contentType=""
    contentName=""
    requiredFile=""
    failedFile="apps/python/sol_weather/sol_weather.py"
    expectedChecksum="abc123def456"
    customName="Sol"
    downloadURL="https://github.com/otherchriso/acsm-checksum-reporter"
    dlcPack=""
    isOriginalContent=""
    notes=""
    ;;
  full)
    driver="Driver Zero"
    contentType="car"
    contentName="ks_ferrari_sf70h"
    requiredFile=""
    failedFile="content/cars/ks_ferrari_sf70h/data.acd"
    expectedChecksum="deadbeef1234567890"
    customName="Ferrari SF70H Server Pack"
    downloadURL="https://github.com/otherchriso/acsm-checksum-reporter"
    dlcPack="Ferrari 70th Anniversary"
    isOriginalContent=""
    notes='<p>Updated physics for competitive racing.</p><p>Version must match server exactly.</p>'
    ;;
  *)
    echo "Unknown scenario: ${SCENARIO}"
    usage
    ;;
esac

echo "Testing checksum_failure template with scenario: ${SCENARIO}"
echo ""

# Parse HTML notes through the same pipeline as checker.sh
if [[ -n "${notes}" ]]; then
  notes=$(parse_notes "${notes}")
fi

# Render the template
message=$(render_template "checksum_failure" \
  "driver=${driver}" \
  "contentType=${contentType}" \
  "contentName=${contentName}" \
  "requiredFile=${requiredFile}" \
  "failedFile=${failedFile}" \
  "expectedChecksum=${expectedChecksum}" \
  "customName=${customName}" \
  "downloadURL=${downloadURL}" \
  "dlcPack=${dlcPack}" \
  "isOriginalContent=${isOriginalContent}" \
  "notes=${notes}")

render_status=$?
if [[ -n "${requiredFile}" ]]; then
  context="${driver} on ${requiredFile}"
else
  context="${driver} on ${contentName}"
fi

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
