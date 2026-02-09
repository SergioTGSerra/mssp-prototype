#!/bin/bash
set -e

#Load env
set -a; source .env; set +a

# Create Keycloak OIDC Client for Mailserver
echo "Configuring Keycloak OIDC Client for Mailserver..."
if podman inspect keycloak >/dev/null 2>&1; then
    podman exec keycloak /opt/keycloak/bin/kcadm.sh config credentials --server http://"${KEYCLOAK_HOSTNAME}" --realm master --user "${KEYCLOAK_ADMIN_USERNAME}" --password "${KEYCLOAK_ADMIN_PASSWORD}"

    # Check if client already exists
    if ! podman exec keycloak /opt/keycloak/bin/kcadm.sh get clients -r netzor -q clientId=mailserver --fields id 2>/dev/null | grep -q '"id"'; then
        echo "Creating 'mailserver' OIDC client..."
        podman exec keycloak /opt/keycloak/bin/kcadm.sh create clients -r netzor \
            -s clientId=mailserver \
            -s enabled=true \
            -s clientAuthenticatorType=client-secret \
            -s secret="${MAILSERVER_OIDC_CLIENT_SECRET}" \
            -s 'redirectUris=["*"]' \
            -s directAccessGrantsEnabled=true \
            -s serviceAccountsEnabled=true \
            -s publicClient=false \
            -s protocol=openid-connect \
            -s 'standardFlowEnabled=true' \
            -s 'attributes={"oauth2.device.authorization.grant.enabled":"true","oidc.ciba.grant.enabled":"false"}' \
            > /dev/null 2>&1 || echo "Client might already exist."
    else
        echo "'mailserver' OIDC client already exists."
    fi
else
    echo "Warning: Keycloak container not found. Skipping Keycloak client creation."
fi

# Start Stalwart
echo "Starting Stalwart Mail Server..."
# We use -d and -t (allocate pseudo-TTY) which often helps keep interactive apps running
podman run -d -t \
    -p 25:25 -p 587:587 -p 465:465 \
    -p 143:143 -p 993:993 -p 4190:4190 \
    -p 110:110 -p 995:995 \
    -p 8080:8080 \
    -v stalwart:/opt/stalwart \
    --add-host "${KEYCLOAK_HOSTNAME}:host-gateway" \
    --name mailserver docker.io/stalwartlabs/stalwart:v0.15.4-alpine

podman network connect waf mailserver 2>/dev/null || true

# Wait for Stalwart to initialize
echo "Waiting for Stalwart to initialize (15s)..."
sleep 15

# Check if Stalwart is running
if ! podman ps | grep -q mailserver; then
    echo "Error: Stalwart container exited unexpectedly."
    echo "Logs:"
    podman logs mailserver --tail 20
    exit 1
fi

# Check if OIDC is already configured
if podman exec mailserver grep -q 'directory."keycloak"' /opt/stalwart/etc/config.toml 2>/dev/null; then
    echo "OIDC configuration already present."
else
    echo "Appending OIDC configuration to config.toml..."
    
    # We append to the config file inside the container
    podman exec mailserver sh -c "cat >> /opt/stalwart/etc/config.toml << 'OIDCEOF'

[directory.\"keycloak\"]
type = \"oidc\"
timeout = \"5s\"
endpoint.url = \"https://${KEYCLOAK_HOSTNAME}/realms/netzor/protocol/openid-connect/userinfo\"
endpoint.method = \"userinfo\"
fields.email = \"email\"
fields.username = \"preferred_username\"
fields.full-name = \"name\"

[directory.\"keycloak\".tls]
implicit = true
allow-invalid-certs = false
OIDCEOF
"
    
    echo "Restarting Stalwart to apply changes..."
    podman restart mailserver
    sleep 5
fi

# Ensure directory is set to 'keycloak' (idempotent check)
if podman exec mailserver grep -q 'directory = "internal"' /opt/stalwart/etc/config.toml 2>/dev/null; then
    echo "Switching authentication directory to 'keycloak'..."
    podman exec mailserver sed -i 's/directory = "internal"/directory = "keycloak"/' /opt/stalwart/etc/config.toml
    podman restart mailserver
    sleep 5
fi