#!/bin/bash

# Import utils and load environment variables
source ./utils.sh
load_env

# Run BunkerWeb AIO
echo "Starting BunkerWeb AIO container..."

podman run -d \
    --name bunkerweb \
    --network=netzor-network \
    --ip ${BUNKERWEB_IP} \
    -p 80:8080/tcp \
    -p 443:8443/tcp \
    -p 443:8443/udp \
    -v bunkerweb:/data:Z \
    -e ADMIN_USERNAME=${BUNKERWEB_ADMIN_USERNAME} \
    -e ADMIN_PASSWORD=${BUNKERWEB_ADMIN_PASSWORD} \
    -e USE_CROWDSEC=yes \
    -e USE_WHITELIST=yes \
    -e WHITELIST_COUNTRY="PT" \
    -e MULTISITE=yes \
    -e SERVER_NAME="${FREEIPA_HOSTNAME} ${KEYCLOAK_HOSTNAME}" \
    -e "${FREEIPA_HOSTNAME}_USE_REVERSE_PROXY=yes" \
    -e "${FREEIPA_HOSTNAME}_REVERSE_PROXY_HOST=https://${FREEIPA_IP}:443" \
    -e "${FREEIPA_HOSTNAME}_SECURITY_MODE=detect" \
    -e "${KEYCLOAK_HOSTNAME}_USE_REVERSE_PROXY=yes" \
    -e "${KEYCLOAK_HOSTNAME}_REVERSE_PROXY_HOST=http://${KEYCLOAK_IP}:8080" \
    -e "${KEYCLOAK_HOSTNAME}_SECURITY_MODE=detect" \
    docker.io/bunkerity/bunkerweb-all-in-one:1.6.6

# Verification
if [ $? -eq 0 ]; then
    echo "BunkerWeb AIO started successfully."
else
    echo "ERROR: Failed to start BunkerWeb AIO."
    exit 1
fi
