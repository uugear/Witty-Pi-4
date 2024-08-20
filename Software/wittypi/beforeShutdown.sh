#!/bin/bash

## Script that replaces the default beforeShutdown.sh of the wittyPi installation.

# Get current directory
cur_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# Get utilities
source "$cur_dir/utilities.sh"

# Verify current wittypi schedule
$ecomoni wittypi check-next-startup

log "Attempting shutdown at $(date)."

# Stop ecomoni service
sudo systemctl stop ecomoni

# Wait for the service to stop
max_delay=30  # maximum time to wait in seconds
i=0
while [ "$(sudo systemctl is-active ecomoni)" == "active" ] && (( $i < $max_delay )); do
    sleep 1
    i=$(($i + 1))
done

if (( $i < $max_delay )); then
  log "Shutdown on $(date) after waiting $i seconds."
else
  log "Force shutdown on $(date) after waiting $i seconds."
fi
