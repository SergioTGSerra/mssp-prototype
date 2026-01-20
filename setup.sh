#!/bin/bash

# Import utils and load environment variables
source ./utils.sh
source .env

# Prompt for domain (only user input required)
read -p "Enter your domain [${DOMAIN}]: " USER_DOMAIN
DOMAIN=${USER_DOMAIN:-$DOMAIN}
update_or_create_env DOMAIN "${DOMAIN}"

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

# 6. Setup Nextcloud
echo ">> Step 6: Installing Nextcloud..."
if [ -f "./nextcloud/setup.sh" ]; then
    ./nextcloud/setup.sh
    if [ $? -ne 0 ]; then
        echo "Error: Nextcloud setup failed. Exiting."
        exit 1
    fi
fi

# # 7. Setup GLPI
# echo ">> Step 7: Installing GLPI..."
# if [ -f "./glpi/setup.sh" ]; then
#     ./glpi/setup.sh
#     if [ $? -ne 0 ]; then
#         echo "Error: GLPI setup failed. Exiting."
#         exit 1
#     fi
# fi

# # 8. Setup IRIS
# echo ">> Step 8: Installing IRIS..."
# if [ -f "./iris/setup.sh" ]; then
#     ./iris/setup.sh
#     if [ $? -ne 0 ]; then
#         echo "Error: IRIS setup failed. Exiting."
#         exit 1
#     fi
# fi

# # 9. Setup Guacamole
# echo ">> Step 9: Installing Guacamole..."
# if [ -f "./guacamole/setup.sh" ]; then
#     ./guacamole/setup.sh
#     if [ $? -ne 0 ]; then
#         echo "Error: Guacamole setup failed. Exiting."
#         exit 1
#     fi
# fi
