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

    # Create stalwart-bind system user in FreeIPA
    freeipa_create_system_account "stalwart-bind" "Stalwart" "Bind" "${STALWART_LDAP_BIND_PASSWORD}" "Stalwart LDAP Bind System Account"

    podman run -d -t \
        --network stalwart_default \
        -p 25:25 -p 587:587 -p 465:465 \
        -p 143:143 -p 993:993 -p 4190:4190 \
        -p 110:110 -p 995:995 \
        -v stalwart:/opt/stalwart \
        --add-host "${KEYCLOAK_HOSTNAME}:host-gateway" \
        --add-host "${FREEIPA_HOSTNAME}:host-gateway" \
        --name mailserver docker.io/stalwartlabs/stalwart:v0.15.5
        
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

    # Configure Stalwart
    if podman exec mailserver grep -q 'directory."keycloak"' /opt/stalwart/etc/config.toml 2>/dev/null; then
        echo "Configuration already present."
    else
        echo "Appending configuration to config.toml..."
        
        # We append to the config file inside the container
        podman exec mailserver sh -c "cat >> /opt/stalwart/etc/config.toml << 'EOF'

[directory.\"keycloak\"]
type = \"oidc\"
timeout = \"5s\"
endpoint.url = \"https://${KEYCLOAK_HOSTNAME}/realms/netzor/protocol/openid-connect/userinfo\"
endpoint.method = \"userinfo\"
fields.email = \"email\"
fields.full-name = \"name\"

[directory.\"keycloak\".tls]
implicit = true
allow-invalid-certs = false

[directory.\"ldap\"]
type = \"ldap\"
url = \"ldap://${FREEIPA_HOSTNAME}:389\"
base-dn = \"cn=users,cn=accounts,dc=netzor,dc=pt\"
timeout = \"10s\"

[directory.\"ldap\".bind]
dn = \"${STALWART_LDAP_BIND_DN}\"
secret = \"${STALWART_LDAP_BIND_PASSWORD}\"

[directory.\"ldap\".bind.auth]
method = \"lookup\"

[directory.\"ldap\".filter]
name = \"(&(objectClass=posixAccount)(mail=?))\"
email = \"(&(objectClass=posixAccount)(mail=?))\"

[directory.\"ldap\".attributes]
name = \"mail\"
class = \"objectClass\"
email = \"mail\"
description = \"cn\"
secret = \"userPassword\"
secret-changed = \"krbLastPwdChange\"

[directory.\"ldap\".tls]
implicit = true
allow-invalid-certs = true

[authentication.master]
user = \"${MAILSERVER_MASTER_USERNAME}\"
secret = \"${MAILSERVER_MASTER_PASSWORD}\"

[email.folders.sent]
name = \"Sent\"
create = true
subscribe = true

[email.folders.trash]
name = \"Trash\"
create = true
subscribe = true

[email.folders.drafts]
name = \"Drafts\"
create = true
subscribe = true

[email.folders.junk]
name = \"Junk\"
create = true
subscribe = true

[email.folders.archive]
name = \"Archive\"
create = true
subscribe = true

[email.folders.shared]
enable = false

[acme.\"letsencrypt\"]
directory = \"https://acme-v02.api.letsencrypt.org/directory\"
challenge = \"dns-01\"
contact = [\"postmaster@${DOMAIN}\"]
domains = [\"${MAILSERVER_HOSTNAME}\"]
cache = \"%{BASE_PATH}%/etc/acme\"
renew-before = \"30d\"
default = true
provider = \"cloudflare\"
secret = \"${CLOUDFLARE_API_TOKEN}\"
polling-interval = \"15s\"
propagation-timeout = \"2m\"
ttl = \"5m\"
timeout = \"30s\"

EOF
"
        
        echo "Switching authentication directory to 'ldap'..."
        podman exec mailserver sed -i 's/directory = "internal"/directory = "ldap"/' /opt/stalwart/etc/config.toml

        echo "Restarting Stalwart to apply changes..."
        podman restart mailserver
        sleep 5
    fi
fi