#!/bin/bash
set -e

#Load env
set -a; source .env; set +a

#Add mailserver-bind user to FreeIPA
echo "Configuring FreeIPA Mailserver Bind User..."
podman exec freeipa bash -c "
    echo '${FREEIPA_ADMIN_PASSWORD}' | kinit admin > /dev/null 2>&1

    if ! ipa user-show mailserver-bind > /dev/null 2>&1; then
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

# Mailserver Client
echo "Configuring Keycloak Client: Mailserver..."
if ! podman exec keycloak /opt/keycloak/bin/kcadm.sh get clients -r netzor -q clientId=${MAILSERVER_OIDC_CLIENT_ID} --fields clientId 2>/dev/null | grep -q "${MAILSERVER_OIDC_CLIENT_ID}"; then
    podman exec keycloak /opt/keycloak/bin/kcadm.sh create clients -r netzor \
        -s clientId="${MAILSERVER_OIDC_CLIENT_ID}" \
        -s enabled=true \
        -s clientAuthenticatorType=client-secret \
        -s secret="${MAILSERVER_OIDC_CLIENT_SECRET}" \
        -s publicClient=false \
        -s standardFlowEnabled=false \
        -s serviceAccountsEnabled=true \
        -s directAccessGrantsEnabled=true > /dev/null 2>&1 || echo "ERROR: Failed to create Mailserver client."
else
    echo "Mailserver client already exists."
fi

#Roundcube Client
echo "Configuring Keycloak Client: Roundcube..."
if ! podman exec keycloak /opt/keycloak/bin/kcadm.sh get clients -r netzor -q clientId=${ROUNDCUBE_OIDC_CLIENT_ID} --fields clientId 2>/dev/null | grep -q "${ROUNDCUBE_OIDC_CLIENT_ID}"; then
    podman exec keycloak /opt/keycloak/bin/kcadm.sh create clients -r netzor \
        -s clientId="${ROUNDCUBE_OIDC_CLIENT_ID}" \
        -s enabled=true \
        -s clientAuthenticatorType=client-secret \
        -s secret="${ROUNDCUBE_OIDC_CLIENT_SECRET}" \
        -s "redirectUris=[\"https://${ROUNDCUBE_HOSTNAME}/*\", \"http://${ROUNDCUBE_HOSTNAME}/*\"]" \
        -s "webOrigins=[\"https://${ROUNDCUBE_HOSTNAME}\", \"http://${ROUNDCUBE_HOSTNAME}\"]" \
        -s publicClient=false \
        -s protocol=openid-connect \
        -s 'defaultClientScopes=["openid", "profile", "email"]' > /dev/null 2>&1
else
    echo "Roundcube client already exists."
fi

echo ">> Starting Mail Services..."
cd "$(dirname "$0")"
PROJECT_NAME=$(basename "$PWD" | sed 's/^[0-9]*_//')
podman-compose -p "$PROJECT_NAME" -f compose.yaml up -d

# Add client_id & client_secret to dovecot-oauth2.conf.ext
podman exec mailserver bash -c "
cat >> /etc/dovecot/dovecot-oauth2.conf.ext << EOF
client_id = ${MAILSERVER_OIDC_CLIENT_ID}
client_secret = ${MAILSERVER_OIDC_CLIENT_SECRET}
tls_allow_invalid_cert = yes
EOF
"

# Add client_id & client_secret to roundcube/oauth2.inc.php
podman cp oauth2.inc.php roundcube:/var/roundcube/config/oauth2.inc.php
podman exec roundcube bash -c "
    sed -i 's/\${ROUNDCUBE_OIDC_CLIENT_ID}/${ROUNDCUBE_OIDC_CLIENT_ID}/g' /var/roundcube/config/oauth2.inc.php
    sed -i 's/\${ROUNDCUBE_OIDC_CLIENT_SECRET}/${ROUNDCUBE_OIDC_CLIENT_SECRET}/g' /var/roundcube/config/oauth2.inc.php
    sed -i 's/\${KEYCLOAK_HOSTNAME}/${KEYCLOAK_HOSTNAME}/g' /var/roundcube/config/oauth2.inc.php
"