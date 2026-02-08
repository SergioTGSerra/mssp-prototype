#!/bin/bash

# Import utils and load environment variables
source ./utils.sh
set -a; source .env; set +a

# 1. Setup Prerequisites (OpenSSL, Podman)
echo ">> Step 0: Checking/Installing Prerequisites..."
if [ -f "./prerequisites.sh" ]; then
    ./prerequisites.sh
    if [ $? -ne 0 ]; then
        echo "Error: Prerequisites setup failed. Exiting."
        exit 1
    fi
fi

# Loop through all numbered folders (01_*, 02_*, ..., nn_*)
for folder in $(ls -d [0-9][0-9]_*/ 2>/dev/null | sort); do
    # Remove trailing slash
    folder="${folder%/}"
    
    # Extract step number and service name
    step_num="${folder%%_*}"
    service_name="${folder#*_}"
    
    echo ">> Step ${step_num}: Installing ${service_name}..."
    
    if [ -f "./${folder}/setup.sh" ]; then
        ./${folder}/setup.sh
        if [ $? -ne 0 ]; then
            echo "Error: ${service_name} setup failed. Exiting."
            exit 1
        fi
    else
        echo "Warning: No setup.sh found in ${folder}, skipping..."
    fi
done

echo ">> All services installed successfully!"