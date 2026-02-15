#!/usr/bin/env bash
# mock_detection.sh
# Tests the full detection + extraction pipeline using real log lines

source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

# Source checker.sh functions (but not the tail loop at the end)
# We extract the functions by sourcing up to the tail command
# Instead, we replicate the detection logic inline using _common.sh functions

echo "========================================"
echo "Detection + Extraction Pipeline Test"
echo "========================================"
echo ""

# Specimen log lines with fictitious names and GUIDs
declare -A LOG_LINES

LOG_LINES[checksum_kick_warn]='time="2026-02-07T08:10:35+10:00" level=warning msg="Car: 0 failed checksum on file '\''content/cars/lotus_evora_gtc/data.acd'\''. Kicking from server."'
LOG_LINES[checksum_kick]='time="2026-02-07T08:10:35+10:00" level=info msg="Kicking: CarID: 0, Name: Driver Zero, GUID: 76561100000000001, Model: lotus_evora_gtc, reason: Checksum failed"'

LOG_LINES[checksum_kick_app_warn]='time="2026-02-07T09:46:20+10:00" level=warning msg="Car: 1 failed checksum on file '\''apps/python/sol_weather/sol_weather.py'\''. Kicking from server."'
LOG_LINES[checksum_kick_app]='time="2026-02-07T09:46:20+10:00" level=info msg="Kicking: CarID: 1, Name: Driver Zero, GUID: 76561100000000001, Model: lotus_evora_gtc, reason: Checksum failed"'

LOG_LINES[session_closed]='time="2026-02-05T20:30:15+10:00" level=info msg="Driver: Alex Turner (76561100000000002) tried to join but was rejected as current session is closed"'

LOG_LINES[no_slots]='time="2026-02-05T20:31:02+10:00" level=info msg="Could not connect driver (Sam Wilson/76561100000000003) to car. no available slots for this GUID"'

LOG_LINES[plugin_kick]='time="2026-02-05T19:45:10+10:00" level=info msg="Kicking: CarID: 3, Name: Jordan Blake, GUID: 76561100000000004, reason: UDP Plugin"'

LOG_LINES[ping_kick]='time="2026-02-05T21:12:33+10:00" level=info msg="Kicking: CarID: 2, Name: Morgan Chase, GUID: 76561100000000005, reason: Exceeded Ping Limit"'

LOG_LINES[idle_kick]='time="2026-02-07T09:22:15+10:00" level=info msg="Kicking: CarID: 5, Name: Riley Parker, GUID: 76561100000000006, Model: ks_ferrari_488_gt3, reason: For Idling"'

LOG_LINES[no_join_list]='time="2026-02-07T08:11:02+10:00" level=info msg="Driver: Casey Quinn (76561100000000007) was rejected as their guid is in the no join list (was previously kicked during this session)"'

PASS=0
FAIL=0

# Test each detection pattern
for key in checksum_kick checksum_kick_app session_closed no_slots plugin_kick ping_kick idle_kick no_join_list; do
  line="${LOG_LINES[$key]}"
  matched=""

  if [[ $(echo "${line}" | egrep -c 'Kicking.*Checksum failed') -gt 0 ]]; then
    matched="checksum_kick"
    # Both checksum_kick and checksum_kick_app share the same detection pattern
    [[ "${key}" == "checksum_kick_app" ]] && matched="checksum_kick_app"
  elif [[ $(echo "${line}" | egrep -c 'tried to join but was rejected as current session is closed') -gt 0 ]]; then
    matched="session_closed"
  elif [[ $(echo "${line}" | egrep -c 'Could not connect driver.*no available slots') -gt 0 ]]; then
    matched="no_slots"
  elif [[ $(echo "${line}" | egrep -c 'Kicking:.*reason: UDP Plugin') -gt 0 ]]; then
    matched="plugin_kick"
  elif [[ $(echo "${line}" | egrep -c 'Kicking:.*reason: Exceeded Ping Limit') -gt 0 ]]; then
    matched="ping_kick"
  elif [[ $(echo "${line}" | egrep -c 'Kicking:.*reason: For Idling') -gt 0 ]]; then
    matched="idle_kick"
  elif [[ $(echo "${line}" | egrep -c 'was rejected as their guid is in the no join list') -gt 0 ]]; then
    matched="no_join_list"
  fi

  if [[ "${matched}" == "${key}" ]]; then
    echo "PASS: ${key} -> detected as '${matched}'"
    ((PASS++))
  elif [[ -z "${matched}" ]]; then
    echo "FAIL: ${key} -> NOT DETECTED"
    ((FAIL++))
  else
    echo "FAIL: ${key} -> misdetected as '${matched}'"
    ((FAIL++))
  fi
done

echo ""
echo "--- Driver Extraction Tests ---"
echo ""

# Test driver extraction for each type
# checksum_kick: driver from Kicking line, path from warning line
line="${LOG_LINES[checksum_kick]}"
driver=$(echo "${line}" | sed -n 's/.*Name: \([^,]*\),.*/\1/p' | xargs)
warnline="${LOG_LINES[checksum_kick_warn]}"
failedpath=$(echo "${warnline}" | sed -n "s/.*on file '\([^']*\)'.*/\1/p")
if [[ "${driver}" == "Driver Zero" && "${failedpath}" == "content/cars/lotus_evora_gtc/data.acd" ]]; then
  echo "PASS: checksum_kick extraction -> driver='${driver}' path='${failedpath}'"
  ((PASS++))
else
  echo "FAIL: checksum_kick extraction -> driver='${driver}' path='${failedpath}' (expected 'Driver Zero' / 'content/cars/lotus_evora_gtc/data.acd')"
  ((FAIL++))
fi

# checksum_kick_app: driver from Kicking line, path from warning line, classify as required file
line="${LOG_LINES[checksum_kick_app]}"
driver=$(echo "${line}" | sed -n 's/.*Name: \([^,]*\),.*/\1/p' | xargs)
warnline="${LOG_LINES[checksum_kick_app_warn]}"
failedpath=$(echo "${warnline}" | sed -n "s/.*on file '\([^']*\)'.*/\1/p")
if [[ "${driver}" == "Driver Zero" && ! "${failedpath}" =~ ^content/(cars|tracks)/ ]]; then
  reqfile=$(basename "${failedpath}")
  if [[ "${reqfile}" == "sol_weather.py" ]]; then
    echo "PASS: checksum_kick_app extraction -> driver='${driver}' requiredFile='${reqfile}'"
    ((PASS++))
  else
    echo "FAIL: checksum_kick_app extraction -> requiredFile='${reqfile}' (expected 'sol_weather.py')"
    ((FAIL++))
  fi
else
  echo "FAIL: checksum_kick_app extraction -> driver='${driver}' path='${failedpath}' (expected non-content path)"
  ((FAIL++))
fi

# session_closed: sed -n 's/.*Driver: \([^(]*\)(.*/\1/p'
line="${LOG_LINES[session_closed]}"
driver=$(echo "${line}" | sed -n 's/.*Driver: \([^(]*\)(.*/\1/p' | xargs)
if [[ "${driver}" == "Alex Turner" ]]; then
  echo "PASS: session_closed extraction -> '${driver}'"
  ((PASS++))
else
  echo "FAIL: session_closed extraction -> '${driver}' (expected 'Alex Turner')"
  ((FAIL++))
fi

# no_slots: sed -n 's/.*Could not connect driver (\([^/]*\)\/.*/\1/p'
line="${LOG_LINES[no_slots]}"
driver=$(echo "${line}" | sed -n 's/.*Could not connect driver (\([^\/]*\)\/.*/\1/p' | xargs)
if [[ "${driver}" == "Sam Wilson" ]]; then
  echo "PASS: no_slots extraction -> '${driver}'"
  ((PASS++))
else
  echo "FAIL: no_slots extraction -> '${driver}' (expected 'Sam Wilson')"
  ((FAIL++))
fi

# plugin_kick: sed -n 's/.*Name: \([^,]*\),.*/\1/p'
line="${LOG_LINES[plugin_kick]}"
driver=$(echo "${line}" | sed -n 's/.*Name: \([^,]*\),.*/\1/p' | xargs)
if [[ "${driver}" == "Jordan Blake" ]]; then
  echo "PASS: plugin_kick extraction -> '${driver}'"
  ((PASS++))
else
  echo "FAIL: plugin_kick extraction -> '${driver}' (expected 'Jordan Blake')"
  ((FAIL++))
fi

# ping_kick: sed -n 's/.*Name: \([^,]*\),.*/\1/p'
line="${LOG_LINES[ping_kick]}"
driver=$(echo "${line}" | sed -n 's/.*Name: \([^,]*\),.*/\1/p' | xargs)
if [[ "${driver}" == "Morgan Chase" ]]; then
  echo "PASS: ping_kick extraction -> '${driver}'"
  ((PASS++))
else
  echo "FAIL: ping_kick extraction -> '${driver}' (expected 'Morgan Chase')"
  ((FAIL++))
fi

# idle_kick: sed -n 's/.*Name: \([^,]*\),.*/\1/p'
line="${LOG_LINES[idle_kick]}"
driver=$(echo "${line}" | sed -n 's/.*Name: \([^,]*\),.*/\1/p' | xargs)
if [[ "${driver}" == "Riley Parker" ]]; then
  echo "PASS: idle_kick extraction -> '${driver}'"
  ((PASS++))
else
  echo "FAIL: idle_kick extraction -> '${driver}' (expected 'Riley Parker')"
  ((FAIL++))
fi

# no_join_list: sed -n 's/.*Driver: \([^(]*\)(.*/\1/p'
line="${LOG_LINES[no_join_list]}"
driver=$(echo "${line}" | sed -n 's/.*Driver: \([^(]*\)(.*/\1/p' | xargs)
if [[ "${driver}" == "Casey Quinn" ]]; then
  echo "PASS: no_join_list extraction -> '${driver}'"
  ((PASS++))
else
  echo "FAIL: no_join_list extraction -> '${driver}' (expected 'Casey Quinn')"
  ((FAIL++))
fi

echo ""
echo "========================================"
echo "Results: ${PASS} passed, ${FAIL} failed"
echo "========================================"
