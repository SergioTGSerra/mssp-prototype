#!/bin/bash
source utils.sh; script_init;

# Create network
podman network create stalwart_default 2>/dev/null || true

# Start Stalwart
echo "Starting Stalwart Mail Server..."
# We use -d and -t (allocate pseudo-TTY) which often helps keep interactive apps running
if podman container exists mailserver; then
  podman start mailserver
else
    # Create Keycloak OIDC Client for Mailserver
    keycloak_create_oidc_client "mailserver" "${MAILSERVER_OIDC_CLIENT_SECRET}" \
        '["*"]' \
        '' \
        '{"oauth2.device.authorization.grant.enabled":"true","oidc.ciba.grant.enabled":"false"}' \
        "directAccessGrantsEnabled=true" \
        "serviceAccountsEnabled=true" \
        "standardFlowEnabled=true"

    podman run -d -t \
        --network stalwart_default \
        -p 25:25 -p 587:587 -p 465:465 \
        -p 143:143 -p 993:993 -p 4190:4190 \
        -p 110:110 -p 995:995 \
        -v stalwart:/opt/stalwart \
        --add-host "${KEYCLOAK_HOSTNAME}:host-gateway" \
        --name mailserver docker.io/stalwartlabs/stalwart:v0.15.5-alpine
        
    podman network connect waf_default mailserver 2>/dev/null || true

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

[authentication.master]
user = \"${MAILSERVER_MASTER_USERNAME}\"
secret = \"${MAILSERVER_MASTER_PASSWORD}\"
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
fi