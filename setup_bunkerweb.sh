#!/bin/bash

# ===========================================
# Setup BunkerWeb AIO (All-In-One)
# ===========================================


# Default Hostnames
FREEIPA_HOSTNAME="ipa.netzor.pt"
KEYCLOAK_HOSTNAME="auth.netzor.pt"

echo "Setting up BunkerWeb AIO..."

# Run BunkerWeb AIO
echo "Starting BunkerWeb AIO container..."

podman run -d \
    --name bunkerweb \
    --network=netzor-network \
    --ip 10.90.0.2 \
    -p 80:8080/tcp \
    -p 443:8443/tcp \
    -p 443:8443/udp \
    -v bunkerweb:/data:Z \
    -e ADMIN_USERNAME=admin \
    -e ADMIN_PASSWORD=ChangeMe123! \
    -e USE_CROWDSEC=yes \
    -e USE_WHITELIST=yes \
    -e WHITELIST_COUNTRY="PT" \
    -e MULTISITE=yes \
    -e SERVER_NAME="${FREEIPA_HOSTNAME} ${KEYCLOAK_HOSTNAME}" \
    -e "${FREEIPA_HOSTNAME}_USE_REVERSE_PROXY=yes" \
    -e "${FREEIPA_HOSTNAME}_REVERSE_PROXY_HOST=https://10.90.0.3:443" \
    -e "${FREEIPA_HOSTNAME}_SECURITY_MODE=detect" \
    -e "${KEYCLOAK_HOSTNAME}_USE_REVERSE_PROXY=yes" \
    -e "${KEYCLOAK_HOSTNAME}_REVERSE_PROXY_HOST=http://10.90.0.4:8080" \
    -e "${KEYCLOAK_HOSTNAME}_SECURITY_MODE=detect" \
    docker.io/bunkerity/bunkerweb-all-in-one:1.6.6

# Verification
if [ $? -eq 0 ]; then
    echo "BunkerWeb AIO started successfully."
    echo "Default Credentials:"
    echo "  User: admin"
    echo "  Pass: ChangeMe123!"
else
    echo "ERROR: Failed to start BunkerWeb AIO."
    exit 1
fi
