#!/bin/bash
source utils.sh; script_init;

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