# ACSM Checksum Reporter

This repo is a set of scripts which solves the following use case:

When someone joins an Assetto Corsa Server Manager server and receives a checksum failure, a message telling everyone the name of the driver and the cause of the checksum failure is sent to a specific Discord server via webhook.

## Assumed pre-requisites

1. A relatively modern Linux-based environment
2. A functioning ACSM multiserver installation
3. GNU coreutils, jq, bash

## Installation

It is recommended to install the system as the same user that ACSM runs as.

1. Create a directory somewhere on the same host as the ACSM installation, and unpack this repo's files there.
2. Copy the `.secrets.example` file as `.secrets`
3. `chmod 640 .secrets`
4. Edit `.secrets` to specify the webhook URL you want to deliver messages to.
6. Copy the `checksum.env.example` file as `checksum.env`
7. `chmod 640 checksum.env`
8. Edit `checksum.env` to specify the path to your uploaded content directory, and the directory above your ACSM multiservers.

### Optional - systemd service

An example unit file is provided in case you'd like to do something like auto-start these scripts when ACSM itself is started.

## How it works, in English

Configuration specific to your system lives in the `checksum.env` file, and the webhook URL (which contains a token) lives in the `.secrets` file.

A parent script, `checksum-manager.sh` initiates child scripts that maintain a reliable log observation surface as servers come and go, and scripts that read the content of those logs and take action when required.

The `latest-linker.sh` child script will poll for log files changing, indicating that new servers are starting, and manage symbolic links so that the `checker.sh` scripts have somewhere constant to watch.

Those `checker.sh` scripts read every line, and when one is found matching the pattern of someone being checksum-kicked, that line and the one before it are parsed. The relevant info is then transmitted to a webhook endpoint.

