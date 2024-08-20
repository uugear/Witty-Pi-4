#!/bin/bash

## Script that replaces the default beforeScript.sh of the wittyPi installation.

# Get current directory
cur_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# Get utilities
source "$cur_dir/utilities.sh"

if wait_network; then
    # Sync system and RTC time
    sync_time

    # Recover from uncompleted update
    if [ -f "$home_dir/UPDATING" ]; then
      $python -m pip uninstall ecomoni -y
      $python -m pip install --no-dependencies $(<"$home_dir/PACKAGE_URL")
      rm "$home_dir/UPDATING"
    fi

    # Get config from AWS
    $ecomoni config

    # Run software update
    $ecomoni update

    # Update the WittyPi scripts
    sudo $ecomoni wittypi install set-scripts
fi
