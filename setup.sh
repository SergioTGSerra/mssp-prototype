#!/bin/bash
source utils.sh; script_init;

# Create logs directory
mkdir -p logs

# 1. Setup Prerequisites (OpenSSL, Podman)
echo ">> Step 0: Checking/Installing Prerequisites..."
if [ -f "./prerequisites.sh" ]; then
    ./prerequisites.sh 2>&1 | tee logs/prerequisites.log
    if [ ${PIPESTATUS[0]} -ne 0 ]; then
        echo "Error: Prerequisites setup failed. Check logs/prerequisites.log. Exiting."
        exit 1
    fi
fi

declare -A pids
declare -A statuses

# Loop through all numbered folders (01_*, 02_*, ..., nn_*)
for folder in $(ls -d [0-9][0-9]_*/ 2>/dev/null | sort); do
    # Remove trailing slash
    folder="${folder%/}"
    
    # Extract step number and service name
    step_num="${folder%%_*}"
    service_name="${folder#*_}"
    
    if [ -f "./${folder}/setup.sh" ]; then
        log_file="logs/${service_name}.log"
        exit_file="logs/.${service_name}.exit"
        
        # Run in background
        (
            ./${folder}/setup.sh > "$log_file" 2>&1
            echo $? > "$exit_file"
        ) &
        
        pids[$service_name]=$!
        statuses[$service_name]="⏳ RUNNING"
    else
        echo "Warning: No setup.sh found in ${folder}, skipping..."
    fi
done

echo "Starting parallel installation. Logs are available in the 'logs' directory."
sleep 2 # Brief pause to allow processes to start before clearing screen

# Monitor loop
all_done=false
while [ "$all_done" = false ]; do
    clear
    echo "=========================================="
    echo "   Netzor Services Installation Status    "
    echo "=========================================="
    
    all_done=true
    # Sort service names for consistent display and loop over them
    for service_name in $(printf '%s\n' "${!pids[@]}" | sort); do
        pid="${pids[$service_name]}"
        
        # Check if process is still running
        if kill -0 "$pid" 2>/dev/null; then
            all_done=false
        else
            if [ "${statuses[$service_name]}" = "⏳ RUNNING" ]; then
                exit_file="logs/.${service_name}.exit"
                # Check exit file
                if [ -f "$exit_file" ]; then
                    exit_code=$(cat "$exit_file")
                    if [ "$exit_code" -eq 0 ]; then
                        statuses[$service_name]="✅ DONE"
                    else
                        statuses[$service_name]="❌ FAILED (See logs/${service_name}.log)"
                    fi
                else
                    statuses[$service_name]="❌ FAILED (No exit code found)"
                fi
            fi
        fi
        
        printf "%-20s %s\n" "$service_name" "${statuses[$service_name]}"
    done
    
    if [ "$all_done" = false ]; then
        sleep 2
    fi
done

# Check if any service failed
for status in "${statuses[@]}"; do
    if [[ "$status" == *"FAILED"* ]]; then
        echo "Error: One or more services failed to install. Check the logs."
        exit 1
    fi
done

# Disable freeipa admin user
podman exec freeipa bash -c "
    echo '${FREEIPA_ADMIN_PASSWORD}' | kinit admin
    ipa user-disable admin
    kdestroy
"

# Disable admin user in master realm keycloak
echo "Blocking admin user in master realm..."
ADMIN_USER_ID=$(podman exec keycloak /opt/keycloak/bin/kcadm.sh get users -r master -q username="${KEYCLOAK_ADMIN_USERNAME}" | jq -r '.[0].id')
if [[ -n "$ADMIN_USER_ID" && "$ADMIN_USER_ID" != "null" ]]; then
    podman exec keycloak /opt/keycloak/bin/kcadm.sh update users/"${ADMIN_USER_ID}" -r master -s enabled=false || {
        echo "ERROR: Failed to block admin user in master realm."
    }
    echo "Admin user blocked successfully in master realm."
else
    echo "ERROR: Admin user not found in master realm."
fi

echo ">> All services installed successfully!"