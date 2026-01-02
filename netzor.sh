#!/bin/bash

# Import utils and load environment variables
source ./utils.sh
load_env

# Prompt for domain (only user input required)
read -p "Enter your domain [${DOMAIN}]: " USER_DOMAIN
DOMAIN=${USER_DOMAIN:-$DOMAIN}
update_or_create_env DOMAIN "${DOMAIN}"

# 1. Setup Prerequisites (OpenSSL, Podman)
echo ">> Step 1: Checking/Installing Prerequisites..."
if [ -f "./setup_prerequisites.sh" ]; then
    ./setup_prerequisites.sh
    if [ $? -ne 0 ]; then
        echo "Error: Prerequisites setup failed. Exiting."
        exit 1
    fi
fi

# 2. Setup BunkerWeb (WAF / Reverse Proxy)
echo ">> Step 2: Installing BunkerWeb (WAF)..."
if [ -f "./bunkerweb/setup.sh" ]; then
    ./bunkerweb/setup.sh
    if [ $? -ne 0 ]; then
        echo "Error: BunkerWeb setup failed. Exiting."
        exit 1
    fi
fi

# 3. Setup FreeIPA
echo ">> Step 3: Installing FreeIPA..."
if [ -f "./freeipa/setup.sh" ]; then
    ./freeipa/setup.sh
    if [ $? -ne 0 ]; then
        echo "Error: FreeIPA setup failed. Exiting."
        exit 1
    fi
fi

# 4. Setup Keycloak
echo ">> Step 4: Installing Keycloak..."
if [ -f "./keycloak/setup.sh" ]; then
    ./keycloak/setup.sh
    if [ $? -ne 0 ]; then
        echo "Error: Keycloak setup failed. Exiting."
        exit 1
    fi
fi

# 5. Setup Mail Services (Mailserver + Roundcube)
echo ">> Step 5: Installing Mail Services..."
if [ -f "./mail/setup.sh" ]; then
    (cd mail && ./setup.sh)
    if [ $? -ne 0 ]; then
        echo "Error: Mail Services setup failed. Exiting."
        exit 1
    fi
fi

# # 7. Setup Nextcloud
# echo ">> Step 7: Installing Nextcloud..."
# if [ -f "./setup_nextcloud.sh" ]; then
#     ./setup_nextcloud.sh
#     if [ $? -ne 0 ]; then
#         echo "Error: Nextcloud setup failed. Exiting."
#         exit 1
#     fi
# fi

# # 8. Setup GLPI
# echo ">> Step 8: Installing GLPI..."
# if [ -f "./setup_glpi.sh" ]; then
#     ./setup_glpi.sh
#     if [ $? -ne 0 ]; then
#         echo "Error: GLPI setup failed. Exiting."
#         exit 1
#     fi
# fi
