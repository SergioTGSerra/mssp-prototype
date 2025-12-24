#!/bin/bash

# Import utils and load environment variables
source ./utils.sh
load_env

# Prompt for main domain (only user input required)
read -p "Enter your main domain [${FQDN}]: " USER_FQDN
FQDN=${USER_FQDN:-$FQDN}
update_or_create_env FQDN "${FQDN}"

# 1. Setup Prerequisites (OpenSSL, Podman)
echo ">> Step 1: Checking/Installing Prerequisites..."
if [ -f "./setup_prerequisites.sh" ]; then
    ./setup_prerequisites.sh
    if [ $? -ne 0 ]; then
        echo "Error: Prerequisites setup failed. Exiting."
        exit 1
    fi
else
    echo "Error: setup_prerequisites.sh not found!"
    exit 1
fi

# 2. Setup BunkerWeb (WAF / Reverse Proxy)
echo ">> Step 2: Installing BunkerWeb (WAF)..."
if [ -f "./setup_bunkerweb.sh" ]; then
    chmod +x ./setup_bunkerweb.sh
    ./setup_bunkerweb.sh
    if [ $? -ne 0 ]; then
        echo "Error: BunkerWeb setup failed. Exiting."
        exit 1
    fi
else
    echo "Error: setup_bunkerweb.sh not found!"
    exit 1
fi

# 3. Setup FreeIPA
echo ">> Step 3: Installing FreeIPA..."
if [ -f "./setup_freeipa.sh" ]; then
    ./setup_freeipa.sh
    if [ $? -ne 0 ]; then
        echo "Error: FreeIPA setup failed. Exiting."
        exit 1
    fi
else
    echo "Error: setup_freeipa.sh not found!"
    exit 1
fi

# 4. Setup Keycloak
echo ">> Step 4: Installing Keycloak..."
if [ -f "./setup_keycloak.sh" ]; then
    ./setup_keycloak.sh
    if [ $? -ne 0 ]; then
        echo "Error: Keycloak setup failed. Exiting."
        exit 1
    fi
else
    echo "Error: setup_keycloak.sh not found!"
    exit 1
fi

# 5. Setup Mail Server
echo ">> Step 5: Installing Mail Server..."
if [ -f "./setup_mailserver.sh" ]; then
    ./setup_mailserver.sh
    if [ $? -ne 0 ]; then
        echo "Error: Mail Server setup failed. Exiting."
        exit 1
    fi
else
    echo "Error: setup_mailserver.sh not found!"
    exit 1
fi