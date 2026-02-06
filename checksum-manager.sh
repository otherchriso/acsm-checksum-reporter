#!/usr/bin/env bash

trap "trap - SIGTERM && kill -- -$$" SIGINT SIGTERM EXIT

# Check required config file
if [[ ! -f checksum.env ]]; then
  echo "Error: checksum.env not found." >&2
  exit 1
fi

source checksum.env

# Validate required environment variable
if [[ -z "${serverspath}" ]]; then
  echo "Error: serverspath is not set in checksum.env." >&2
  exit 1
fi

if [[ ! -d "${serverspath}" ]]; then
  echo "Error: serverspath '${serverspath}' does not exist." >&2
  exit 1
fi

# Verify child scripts exist and are executable
if [[ ! -x ./latest-linker.sh ]]; then
  echo "Error: latest-linker.sh not found or not executable." >&2
  exit 1
fi

if [[ ! -x ./checker.sh ]]; then
  echo "Error: checker.sh not found or not executable." >&2
  exit 1
fi

echo "Checksum checker started."

# Spawn the script which rotates logs every time a new server starts
$(./latest-linker.sh) &

for dir in "${serverspath}"*/assetto/logs/session/; do
  $(./checker.sh "${dir}latest.log") &   
done

sleep infinity
