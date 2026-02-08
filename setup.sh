#!/bin/bash

# Import utils and load environment variables
source ./utils.sh
set -a; source .env; set +a

# 1. Setup Prerequisites (OpenSSL, Podman)
echo ">> Step 1: Checking/Installing Prerequisites..."
if [ -f "./prerequisites.sh" ]; then
    ./prerequisites.sh
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
    ./mail/setup.sh
    if [ $? -ne 0 ]; then
        echo "Error: Mail Services setup failed. Exiting."
        exit 1
    fi
fi

# 6. Setup Frappe
echo ">> Step 6: Installing Frappe..."
if [ -f "./frappe/setup.sh" ]; then
    ./frappe/setup.sh
    if [ $? -ne 0 ]; then
        echo "Error: Frappe setup failed. Exiting."
        exit 1
    fi
fi

# 7. Setup GLPI
echo ">> Step 7: Installing GLPI..."
if [ -f "./glpi/setup.sh" ]; then
    ./glpi/setup.sh
    if [ $? -ne 0 ]; then
        echo "Error: GLPI setup failed. Exiting."
        exit 1
    fi
fi

# 8. Setup IRIS
echo ">> Step 8: Installing IRIS..."
if [ -f "./iris/setup.sh" ]; then
    ./iris/setup.sh
    if [ $? -ne 0 ]; then
        echo "Error: IRIS setup failed. Exiting."
        exit 1
    fi
fi

# 9. Setup Jumpserver
echo ">> Step 9: Installing Jumpserver..."
if [ -f "./jumpserver/setup.sh" ]; then
    ./jumpserver/setup.sh
    if [ $? -ne 0 ]; then
        echo "Error: Jumpserver setup failed. Exiting."
        exit 1
    fi
fi

# 10. Setup Nextcloud
echo ">> Step 10: Installing Nextcloud..."
if [ -f "./nextcloud-aio/setup.sh" ]; then
    ./nextcloud-aio/setup.sh
    if [ $? -ne 0 ]; then
        echo "Error: Nextcloud setup failed. Exiting."
        exit 1
    fi
fi