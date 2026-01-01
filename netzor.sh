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
if [ -f "./setup_bunkerweb.sh" ]; then
    chmod +x ./setup_bunkerweb.sh
    ./setup_bunkerweb.sh
    if [ $? -ne 0 ]; then
        echo "Error: BunkerWeb setup failed. Exiting."
        exit 1
    fi
fi

# 3. Setup FreeIPA
echo ">> Step 3: Installing FreeIPA..."
if [ -f "./setup_freeipa.sh" ]; then
    ./setup_freeipa.sh
    if [ $? -ne 0 ]; then
        echo "Error: FreeIPA setup failed. Exiting."
        exit 1
    fi
fi

# 4. Setup Keycloak
echo ">> Step 4: Installing Keycloak..."
if [ -f "./setup_keycloak.sh" ]; then
    ./setup_keycloak.sh
    if [ $? -ne 0 ]; then
        echo "Error: Keycloak setup failed. Exiting."
        exit 1
    fi
fi

# 5. Setup Mail Server
echo ">> Step 5: Installing Mail Server..."
if [ -f "./setup_mailserver.sh" ]; then
    ./setup_mailserver.sh
    if [ $? -ne 0 ]; then
        echo "Error: Mail Server setup failed. Exiting."
        exit 1
    fi
fi

# 6. Setup Roundcube
echo ">> Step 6: Installing Roundcube..."
if [ -f "./setup_roundcube.sh" ]; then
    ./setup_roundcube.sh
    if [ $? -ne 0 ]; then
        echo "Error: Roundcube setup failed. Exiting."
        exit 1
    fi
fi

# 7. Setup Nextcloud
echo ">> Step 7: Installing Nextcloud..."
if [ -f "./setup_nextcloud.sh" ]; then
    ./setup_nextcloud.sh
    if [ $? -ne 0 ]; then
        echo "Error: Nextcloud setup failed. Exiting."
        exit 1
    fi
fi

# 8. Setup GLPI
echo ">> Step 8: Installing GLPI..."
if [ -f "./setup_glpi.sh" ]; then
    ./setup_glpi.sh
    if [ $? -ne 0 ]; then
        echo "Error: GLPI setup failed. Exiting."
        exit 1
    fi
fi
