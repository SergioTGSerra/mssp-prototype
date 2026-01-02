#!/bin/bash

setup_freeipa_user() {
    echo "Configuring FreeIPA Mailserver Bind User..."
    if podman container exists freeipa; then
        podman exec freeipa bash -c "
            echo '${FREEIPA_ADMIN_PASSWORD}' | kinit admin > /dev/null 2>&1
            if ! ipa user-show mailserver-bind >/dev/null 2>&1; then
                ipa user-add mailserver-bind \
                    --first=MailServer \
                    --last=Bind \
                    --cn='Mail Server Bind System Account' \
                    --shell=/sbin/nologin
            fi
            ipa group-add-member system-accounts --users=mailserver-bind > /dev/null 2>&1 || true
            echo -e '${MAILSERVER_LDAP_BIND_PASSWORD}\n${MAILSERVER_LDAP_BIND_PASSWORD}' | ipa passwd mailserver-bind > /dev/null 2>&1
            kdestroy
        "
    else
        echo "WARNING: FreeIPA container not found. Skipping user creation."
        # Not exiting because maybe it's remote? But context says local.
    fi
}

setup_keycloak_clients() {
    if ! podman container exists keycloak; then
        echo "WARNING: Keycloak container not found. Skipping client configuration."
        return
    fi

    # Mailserver Client
    echo "Configuring Keycloak Client: Mailserver..."
    MS_UUID=$(podman exec keycloak /opt/keycloak/bin/kcadm.sh get clients -r netzor -q clientId=${MAILSERVER_OIDC_CLIENT_ID} --fields id --format csv --noquotes 2>/dev/null || true)
    
    if [ -n "$MS_UUID" ]; then
        echo "Updating Mailserver client..."
        podman exec keycloak /opt/keycloak/bin/kcadm.sh update clients/$MS_UUID -r netzor \
            -s enabled=true \
            -s clientAuthenticatorType=client-secret \
            -s secret="${MAILSERVER_OIDC_CLIENT_SECRET}" \
            -s publicClient=false \
            -s standardFlowEnabled=false \
            -s serviceAccountsEnabled=true \
            -s directAccessGrantsEnabled=true > /dev/null 2>&1
    else
        echo "Creating Mailserver client..."
        podman exec keycloak /opt/keycloak/bin/kcadm.sh create clients -r netzor \
            -s clientId="${MAILSERVER_OIDC_CLIENT_ID}" \
            -s enabled=true \
            -s clientAuthenticatorType=client-secret \
            -s secret="${MAILSERVER_OIDC_CLIENT_SECRET}" \
            -s publicClient=false \
            -s standardFlowEnabled=false \
            -s serviceAccountsEnabled=true \
            -s directAccessGrantsEnabled=true > /dev/null 2>&1
    fi

    # Roundcube Client
    echo "Configuring Keycloak Client: Roundcube..."
    RC_UUID=$(podman exec keycloak /opt/keycloak/bin/kcadm.sh get clients -r netzor -q clientId=${ROUNDCUBE_OIDC_CLIENT_ID} --fields id --format csv --noquotes 2>/dev/null || true)

    if [ -n "$RC_UUID" ]; then
         echo "Updating Roundcube client..."
         podman exec keycloak /opt/keycloak/bin/kcadm.sh update clients/$RC_UUID -r netzor \
            -s enabled=true \
            -s clientAuthenticatorType=client-secret \
            -s secret="${ROUNDCUBE_OIDC_CLIENT_SECRET}" \
            -s "redirectUris=[\"http://${ROUNDCUBE_HOSTNAME}/*\", \"https://${ROUNDCUBE_HOSTNAME}/*\"]" \
            -s "webOrigins=[\"http://${ROUNDCUBE_HOSTNAME}\", \"https://${ROUNDCUBE_HOSTNAME}\"]" \
            -s publicClient=false \
            -s protocol=openid-connect \
            -s 'defaultClientScopes=["openid", "profile", "email"]' > /dev/null 2>&1
    else
         echo "Creating Roundcube client..."
         podman exec keycloak /opt/keycloak/bin/kcadm.sh create clients -r netzor \
            -s clientId="${ROUNDCUBE_OIDC_CLIENT_ID}" \
            -s enabled=true \
            -s clientAuthenticatorType=client-secret \
            -s secret="${ROUNDCUBE_OIDC_CLIENT_SECRET}" \
            -s "redirectUris=[\"http://${ROUNDCUBE_HOSTNAME}/*\", \"https://${ROUNDCUBE_HOSTNAME}/*\"]" \
            -s "webOrigins=[\"http://${ROUNDCUBE_HOSTNAME}\", \"https://${ROUNDCUBE_HOSTNAME}\"]" \
            -s publicClient=false \
            -s protocol=openid-connect \
            -s 'defaultClientScopes=["openid", "profile", "email"]' > /dev/null 2>&1
    fi
}

prepare_configs() {
    # 1. Dovecot OAuth2 Config (Host bind mount)
    cat > dovecot-oauth2.conf.ext << EOF
introspection_url = http://${KEYCLOAK_HOSTNAME}/realms/netzor/protocol/openid-connect/token/introspect
introspection_mode = post
client_id = ${MAILSERVER_OIDC_CLIENT_ID}
client_secret = ${MAILSERVER_OIDC_CLIENT_SECRET}
force_introspection = yes
username_attribute = email
active_attribute = active
active_value = true
EOF

    # 2. Mailserver Dovecot Config (Volume population)
    # We use a temp container to write to the volume
    if ! podman volume exists mailserver-config; then
        podman volume create mailserver-config > /dev/null 2>&1
    fi
    
    # Check if we should overwrite or just ensure existence. For now, we overwrite to ensure latest config.
    podman run --rm -v mailserver-config:/tmp/docker-mailserver:Z docker.io/library/busybox:latest sh -c "cat > /tmp/docker-mailserver/dovecot.cf << EOC
ssl = yes
disable_plaintext_auth = no
mail_uid = 5000
mail_gid = 5000
auth_mechanisms = plain login oauthbearer xoauth2
passdb {
  driver = oauth2
  mechanisms = oauthbearer xoauth2
  args = /etc/dovecot/dovecot-oauth2.conf.ext
}
EOC
cat > /tmp/docker-mailserver/postfix-main.cf << EOC
smtpd_sasl_mech_list = plain login oauthbearer xoauth2
smtpd_sasl_security_options = noanonymous
smtpd_sasl_type = dovecot
smtpd_sasl_path = /dev/shm/sasl-auth.sock
smtpd_sasl_auth_enable = yes
EOC"

    # 3. Roundcube Config (Volume population)
    if ! podman volume exists roundcube-config; then
        podman volume create roundcube-config > /dev/null 2>&1
    fi

    # Create config content in a variable or temp file
    cat > config.inc.php << EOF
<?php
\$config['db_dsnw'] = 'sqlite:////var/roundcube/db/sqlite.db';
\$config['proxy_whitelist'] = ['*', 'localhost', '127.0.0.1'];
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

\$config['plugins'] = array_filter(array_map('trim', explode(',', getenv('ROUNDCUBEMAIL_PLUGINS') ?: '')));

// Debugging
\$config['debug_level'] = 1;
\$config['log_driver'] = 'stdout';
\$config['imap_debug'] = true;
\$config['smtp_debug'] = true;
// OAuth2 Configuration - Read from Env
\$config['oauth_provider'] = getenv('ROUNDCUBEMAIL_OAUTH_PROVIDER');
\$config['oauth_provider_name'] = getenv('ROUNDCUBEMAIL_OAUTH_PROVIDER_NAME');
\$config['oauth_client_id'] = getenv('ROUNDCUBEMAIL_OAUTH_CLIENT_ID');
\$config['oauth_client_secret'] = getenv('ROUNDCUBEMAIL_OAUTH_CLIENT_SECRET');
\$config['oauth_auth_uri'] = getenv('ROUNDCUBEMAIL_OAUTH_AUTH_URI');
\$config['oauth_token_uri'] = getenv('ROUNDCUBEMAIL_OAUTH_TOKEN_URI');
\$config['oauth_identity_uri'] = getenv('ROUNDCUBEMAIL_OAUTH_IDENTITY_URI');
\$config['oauth_verify_peer'] = filter_var(getenv('ROUNDCUBEMAIL_OAUTH_VERIFY_PEER'), FILTER_VALIDATE_BOOLEAN);
\$config['oauth_scope'] = getenv('ROUNDCUBEMAIL_OAUTH_SCOPE');
\$config['oauth_identity_fields'] = array_filter(array_map('trim', explode(',', getenv('ROUNDCUBEMAIL_OAUTH_IDENTITY_FIELDS') ?: 'email')));
\$config['oauth_login_redirect'] = filter_var(getenv('ROUNDCUBEMAIL_OAUTH_LOGIN_REDIRECT'), FILTER_VALIDATE_BOOLEAN);


EOF

    # Write to volume
    podman run --rm -i -v roundcube-config:/tmp/roundcube:Z -w /tmp/roundcube docker.io/library/busybox:latest sh -c 'cat > config.inc.php && chown 33:33 config.inc.php' < config.inc.php
    rm config.inc.php
}

echo ">> Setting up Mailchain Dependencies..."
setup_freeipa_user
setup_keycloak_clients
prepare_configs

echo ">> Resolving Container IPs for Compose..."
# We need to resolve keycloak and mailserver (if it was static, but it's not)
# Better: resolve keycloak container IP
if podman container exists keycloak; then
    KEYCLOAK_CONTAINER_IP=$(podman inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' keycloak | head -n 1)
    if [ -z "$KEYCLOAK_CONTAINER_IP" ]; then
        # Fallback for podman < 4 or some setups, look at specific networks?
        # Assuming bridge mode, it has an IP.
        KEYCLOAK_CONTAINER_IP="10.88.0.1" # Fallback/Dummy, should not happen if running
    fi
else
    KEYCLOAK_CONTAINER_IP="127.0.0.1" # Just to pass validation if Keycloak is down
fi
export KEYCLOAK_CONTAINER_IP
echo "Keycloak IP: ${KEYCLOAK_CONTAINER_IP}"

echo ">> Starting Mail Services..."
podman-compose -f compose.yaml up -d
