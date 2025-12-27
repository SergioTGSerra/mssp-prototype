#!/bin/bash

# Load environment variables
if [ -f .env ]; then
    set -a
    source .env
    set +a
else
    echo "ERROR: .env file not found."
    exit 1
fi

if [ -z "$FREEIPA_ADMIN_PASSWORD" ]; then
    read -s -p "Enter FreeIPA 'admin' password: " FREEIPA_ADMIN_PASSWORD
    if [ -z "$FREEIPA_ADMIN_PASSWORD" ]; then
        echo "ERROR: Password is required to create system accounts."
        exit 1
    fi
fi

podman exec freeipa bash -c "
    # Authenticate as admin
    echo '${FREEIPA_ADMIN_PASSWORD}' | kinit admin

    # Create mailserver-bind system user if not exists
    if ! ipa user-show mailserver-bind >/dev/null 2>&1; then
        ipa user-add mailserver-bind \
            --first=MailServer \
            --last=Bind \
            --cn='Mail Server Bind System Account' \
            --shell=/sbin/nologin
    fi

    # Add user to system-accounts group
    ipa group-add-member system-accounts --users=mailserver-bind 2>/dev/null || true

    # Set password
    echo -e '${MAILSERVER_LDAP_BIND_PASSWORD}\n${MAILSERVER_LDAP_BIND_PASSWORD}' | ipa passwd mailserver-bind

    # Destroy Kerberos ticket
    kdestroy
"

# Create or Update Mailserver client in Keycloak
echo "Configuring Mailserver Keycloak client..."
MS_UUID=$(podman exec keycloak /opt/keycloak/bin/kcadm.sh get clients -r netzor -q clientId=${MAILSERVER_OIDC_CLIENT_ID} --fields id --format csv --noquotes 2>/dev/null || true)

if [ -n "$MS_UUID" ]; then
    echo "Mailserver client exists (ID: $MS_UUID). Updating..."
    if podman exec keycloak /opt/keycloak/bin/kcadm.sh update clients/$MS_UUID -r netzor \
        -s enabled=true \
        -s clientAuthenticatorType=client-secret \
        -s secret="${MAILSERVER_OIDC_CLIENT_SECRET}" \
        -s publicClient=false \
        -s standardFlowEnabled=false \
        -s serviceAccountsEnabled=true \
        -s directAccessGrantsEnabled=true \
        > /dev/null 2>&1; then
        echo "Mailserver client updated successfully."
    else
        echo "ERROR: Failed to update Mailserver client."
    fi
else
    echo "Creating Mailserver client..."
    if podman exec keycloak /opt/keycloak/bin/kcadm.sh create clients -r netzor \
        -s clientId="${MAILSERVER_OIDC_CLIENT_ID}" \
        -s enabled=true \
        -s clientAuthenticatorType=client-secret \
        -s secret="${MAILSERVER_OIDC_CLIENT_SECRET}" \
        -s publicClient=false \
        -s standardFlowEnabled=false \
        -s serviceAccountsEnabled=true \
        -s directAccessGrantsEnabled=true \
        > /dev/null 2>&1; then
        echo "Mailserver client created successfully."
    else
        echo "ERROR: Failed to create Mailserver client."
    fi
fi

# Populate config volume with custom Dovecot configuration
podman volume create mailserver-config > /dev/null 2>&1
podman run --rm -v mailserver-config:/tmp/docker-mailserver:Z docker.io/library/busybox:latest sh -c "cat > /tmp/docker-mailserver/dovecot.cf << EOF
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
EOF"

# Create local config files for mounting
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

# Remove existing container
podman rm -f mailserver > /dev/null 2>&1 || true

podman run -d \
  --name mailserver \
  --hostname ${MAILSERVER_HOSTNAME} \
  --ip ${MAILSERVER_IP} \
  --network=netzor-network \
  --add-host ${KEYCLOAK_HOSTNAME}:10.5.81.153 \
  -p 25:25 \
  -p 465:465 \
  -p 587:587 \
  -p 993:993 \
  -p 143:143 \
  -v mailserver-data:/var/mail:Z \
  -v mailserver-state:/var/mail-state/:Z \
  -v mailserver-logs:/var/log/mail/:Z \
  -v mailserver-config:/tmp/docker-mailserver:Z \
  -v $(pwd)/dovecot-oauth2.conf.ext:/etc/dovecot/dovecot-oauth2.conf.ext:Z \
  -e ACCOUNT_PROVISIONER=LDAP \
  -e LDAP_SERVER_HOST=ldap://${FREEIPA_IP} \
  -e LDAP_SEARCH_BASE="cn=accounts,${FREEIPA_BASE_DN}" \
  -e LDAP_BIND_DN="${MAILSERVER_LDAP_BIND_DN}" \
  -e LDAP_BIND_PW="${MAILSERVER_LDAP_BIND_PASSWORD}" \
  -e LDAP_QUERY_FILTER_USER="(&(objectClass=inetOrgPerson)(mail=%s)(!(|(uid=admin)(memberOf=cn=system-accounts,${FREEIPA_GROUP_DN}))))" \
  -e LDAP_QUERY_FILTER_GROUP="(&(objectClass=groupOfNames)(mail=%s))" \
  -e LDAP_QUERY_FILTER_ALIAS="(&(objectClass=inetOrgPerson)(mail=%s)(!(|(uid=admin)(memberOf=cn=system-accounts,${FREEIPA_GROUP_DN}))))" \
  -e LDAP_QUERY_FILTER_DOMAIN="(|(&(mail=*@%s)(objectClass=inetOrgPerson))(&(mailGroupMember=*@%s)(objectClass=groupOfNames)))" \
  -e DOVECOT_PASS_FILTER="(&(objectClass=inetOrgPerson)(uid=%n)(!(|(uid=admin)(memberOf=cn=system-accounts,${FREEIPA_GROUP_DN}))))" \
  -e DOVECOT_USER_FILTER="(&(objectClass=inetOrgPerson)(uid=%n)(!(|(uid=admin)(memberOf=cn=system-accounts,${FREEIPA_GROUP_DN}))))" \
  -e DOVECOT_AUTH_BIND=yes \
  -e ENABLE_OAUTH2=1 \
  -e OAUTH2_INTROSPECTION_URL="http://${KEYCLOAK_HOSTNAME}/realms/netzor/protocol/openid-connect/token/introspect" \
  -e OAUTH2_USERNAME_ATTRIBUTE=email \
  -e ENABLE_SASLAUTHD=1 \
  -e SASLAUTHD_MECHANISMS=ldap \
  -e SASLAUTHD_LDAP_SERVER=ldap://${FREEIPA_IP} \
  -e SASLAUTHD_LDAP_BIND_DN="${MAILSERVER_LDAP_BIND_DN}" \
  -e SASLAUTHD_LDAP_PASSWORD="${MAILSERVER_LDAP_BIND_PASSWORD}" \
  -e SASLAUTHD_LDAP_SEARCH_BASE="cn=accounts,${FREEIPA_BASE_DN}" \
  -e SASLAUTHD_LDAP_FILTER="(&(objectClass=inetOrgPerson)(uid=%U)(!(|(uid=admin)(memberOf=cn=system-accounts,${FREEIPA_GROUP_DN}))))" \
  -e POSTMASTER_ADDRESS=postmaster@${DOMAIN} \
  -e ENABLE_RSPAMD=1 \
  -e ENABLE_CLAMAV=1 \
  -e ENABLE_FAIL2BAN=1 \
  --cap-add NET_ADMIN \
  --restart=always \
  ghcr.io/docker-mailserver/docker-mailserver:15.1.0