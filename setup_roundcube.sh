#!/bin/bash
set -e

# Load environment variables
if [ -f .env ]; then
    set -a
    source .env
    set +a
else
    echo "ERROR: .env file not found."
    exit 1
fi

# Create Roundcube client
# Create or Update Roundcube client
echo "Configuring Roundcube client..."
RC_UUID=$(podman exec keycloak /opt/keycloak/bin/kcadm.sh get clients -r netzor -q clientId=roundcube --fields id --format csv --noquotes 2>/dev/null || true)

if [ -n "$RC_UUID" ]; then
    echo "Roundcube client exists check (ID: $RC_UUID). Updating..."
    if podman exec keycloak /opt/keycloak/bin/kcadm.sh update clients/$RC_UUID -r netzor \
        -s enabled=true \
        -s clientAuthenticatorType=client-secret \
        -s secret="${ROUNDCUBE_OIDC_CLIENT_SECRET}" \
        -s "redirectUris=[\"http://${ROUNDCUBE_HOSTNAME}/*\", \"https://${ROUNDCUBE_HOSTNAME}/*\"]" \
        -s "webOrigins=[\"http://${ROUNDCUBE_HOSTNAME}\", \"https://${ROUNDCUBE_HOSTNAME}\"]" \
        -s publicClient=false \
        -s protocol=openid-connect \
        -s 'defaultClientScopes=["openid", "profile", "email"]' \
        > /dev/null 2>&1; then
        echo "Roundcube client updated successfully."
    else
        echo "ERROR: Failed to update Roundcube client."
    fi
else
    echo "Creating Roundcube client..."
    if podman exec keycloak /opt/keycloak/bin/kcadm.sh create clients -r netzor \
        -s clientId="${ROUNDCUBE_OIDC_CLIENT_ID}" \
        -s enabled=true \
        -s clientAuthenticatorType=client-secret \
        -s secret="${ROUNDCUBE_OIDC_CLIENT_SECRET}" \
        -s "redirectUris=[\"http://${ROUNDCUBE_HOSTNAME}/*\", \"https://${ROUNDCUBE_HOSTNAME}/*\"]" \
        -s "webOrigins=[\"http://${ROUNDCUBE_HOSTNAME}\", \"https://${ROUNDCUBE_HOSTNAME}\"]" \
        -s publicClient=false \
        -s protocol=openid-connect \
        -s 'defaultClientScopes=["openid", "profile", "email"]' \
        > /dev/null 2>&1; then
        echo "Roundcube client created successfully."
    else
        echo "ERROR: Failed to create Roundcube client."
    fi
fi

# Prepare Roundcube Config Volume
podman volume create roundcube-config > /dev/null 2>&1 || true

# Create config files
# Create temporary config files on host
cat > config.inc.php << EOF
<?php
\$config['db_dsnw'] = 'sqlite:////var/roundcube/db/sqlite.db';
\$config['proxy_whitelist'] = ['${BUNKERWEB_IP}', '10.90.0.2'];
\$config['use_https'] = true;
\$config['default_host'] = '${MAILSERVER_HOSTNAME}';
\$config['smtp_server'] = '${MAILSERVER_HOSTNAME}';
\$config['smtp_port'] = 25;
\$config['imap_port'] = 143;
\$config['imap_conn_options'] = [
  'ssl' => [
     'verify_peer' => false,
     'verify_peer_name' => false,
     'allow_self_signed' => true
   ]
];
\$config['smtp_conn_options'] = [
  'ssl' => [
     'verify_peer' => false,
     'verify_peer_name' => false,
     'allow_self_signed' => true
   ]
];

\$config['plugins'] = [];

// Debugging
\$config['debug_level'] = 1;
\$config['log_driver'] = 'stdout';
\$config['imap_debug'] = true;
\$config['smtp_debug'] = true;
\$config['ldap_debug'] = true;

// OAuth2 Configuration
\$config['oauth_provider'] = 'generic';
\$config['oauth_provider_name'] = 'Keycloak';
\$config['oauth_client_id'] = '${ROUNDCUBE_OIDC_CLIENT_ID}';
\$config['oauth_client_secret'] = '${ROUNDCUBE_OIDC_CLIENT_SECRET}';
\$config['oauth_auth_uri'] = 'http://${KEYCLOAK_HOSTNAME}/realms/netzor/protocol/openid-connect/auth';
\$config['oauth_token_uri'] = 'http://${KEYCLOAK_HOSTNAME}/realms/netzor/protocol/openid-connect/token';
\$config['oauth_identity_uri'] = 'http://${KEYCLOAK_HOSTNAME}/realms/netzor/protocol/openid-connect/userinfo';
\$config['oauth_verify_peer'] = false;
\$config['oauth_scope'] = 'email openid profile';
\$config['oauth_identity_fields'] = ['email'];
\$config['oauth_login_redirect'] = true;
EOF

# Copy config files to volume
podman run --rm -i -v roundcube-config:/tmp/roundcube:Z -w /tmp/roundcube docker.io/library/busybox:latest sh -c 'cat > config.inc.php' < config.inc.php

# Cleanup temp files
rm config.inc.php

# Remove existing container
podman rm -f roundcube > /dev/null 2>&1 || true

echo "Starting Roundcube..."
podman run -d \
    --name roundcube \
    --network=netzor-network \
    --ip ${ROUNDCUBE_IP} \
    --add-host ${MAILSERVER_HOSTNAME}:10.90.0.6 \
    --add-host ${KEYCLOAK_HOSTNAME}:10.5.81.153 \
    -e ROUNDCUBEMAIL_DB_TYPE=sqlite \
    -e ROUNDCUBEMAIL_DEFAULT_HOST="${MAILSERVER_HOSTNAME}" \
    -e ROUNDCUBEMAIL_DEFAULT_PORT=143 \
    -e ROUNDCUBEMAIL_SMTP_SERVER="${MAILSERVER_HOSTNAME}" \
    -e ROUNDCUBEMAIL_SMTP_PORT=25 \
    -v roundcube-config:/var/www/html/config:Z \
    docker.io/roundcube/roundcubemail:latest

echo "Roundcube started at http://${ROUNDCUBE_IP}"
