#!/bin/bash

## Script that replaces the default afterStartup.sh of the wittyPi installation.

# Get current directory
cur_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# Get utilities
source "$cur_dir/utilities.sh"

# Verify current wittypi schedule
$ecomoni wittypi check-schedule
$ecomoni wittypi check-next-shutdown

# Start ecomoni service
sudo systemctl start ecomoni
