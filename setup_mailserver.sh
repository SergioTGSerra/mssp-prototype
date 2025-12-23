#!/bin/bash

# ===========================================
# Check FreeIPA dependency
# ===========================================
echo "Checking FreeIPA dependency..."

if ! podman ps --format "{{.Names}}" | grep -q "^freeipa$"; then
    echo "ERROR: FreeIPA container is not running!"
    echo "Please run setup_freeipa.sh first and wait for it to complete."
    exit 1
fi

# Use environment variables from netzor.sh or defaults
DOMAIN="${NETZOR_DOMAIN:-netzor.pt}"
REALM="${NETZOR_REALM:-netzor.pt}"
MAIL_HOSTNAME="mail.${DOMAIN}"

# Generate random password for mailserver-bind system account
MAILSERVER_BIND_PASSWORD=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9')

# Calculate Base DN from Realm (e.g., netzor.pt -> dc=netzor,dc=pt)
IPA_BASE_DN="dc=$(echo $REALM | sed 's/\./,dc=/g')"
IPA_BIND_DN="uid=mailserver-bind,cn=users,cn=accounts,${IPA_BASE_DN}"
IPA_SEARCH_BASE="cn=accounts,${IPA_BASE_DN}"

# Save credentials to temp file for netzor.sh
if [ -n "$NETZOR_CREDENTIALS_FILE" ]; then
    cat >> "$NETZOR_CREDENTIALS_FILE" << EOF
MAILSERVER_BIND_PASSWORD="${MAILSERVER_BIND_PASSWORD}"
EOF
fi

# ===========================================
# Create System Account in FreeIPA
# ===========================================
echo "Creating system account for Mail Server integration..."
# We need the admin password to create users. 
# Attempt to find it if not exported (though netzor.sh exports credentials file source, 
# the actual password variable might be available if netzor.sh sourced it).
# Logic in setup_keycloak.sh assumes env vars or saved credentials.
# We will check if FREEIPA_ADMIN_PASSWORD is set.

if [ -z "$FREEIPA_ADMIN_PASSWORD" ] && [ -n "$NETZOR_CREDENTIALS_FILE" ]; then
    source "$NETZOR_CREDENTIALS_FILE"
fi

if [ -z "$FREEIPA_ADMIN_PASSWORD" ]; then
    echo "WARNING: FREEIPA_ADMIN_PASSWORD not found."
    read -s -p "Enter FreeIPA 'admin' password: " FREEIPA_ADMIN_PASSWORD
    echo ""
    if [ -z "$FREEIPA_ADMIN_PASSWORD" ]; then
        echo "ERROR: Password is required to create system accounts."
        exit 1
    fi
fi

podman exec freeipa bash -c "
    # Authenticate as admin
    echo '${FREEIPA_ADMIN_PASSWORD}' | kinit admin

    # Create system accounts group if not exists
    if ! ipa group-show system-accounts >/dev/null 2>&1; then
        ipa group-add system-accounts --desc='System Accounts (No Password Expiry)'
        ipa pwpolicy-add system-accounts --maxlife=0 --minlife=0 --history=0 --minclasses=0 --minlength=8 --priority=1
    fi

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
    echo -e '${MAILSERVER_BIND_PASSWORD}\n${MAILSERVER_BIND_PASSWORD}' | ipa passwd mailserver-bind

    # Destroy Kerberos ticket
    kdestroy
"

echo "System account 'mailserver-bind' created/updated."

# ===========================================
# Deploy Mail Server
# ===========================================
echo "Starting Mail Server..."

mkdir -p ./docker-data/mail-data
mkdir -p ./docker-data/mail-state
mkdir -p ./docker-data/mail-logs
mkdir -p ./docker-data/config

# Create custom Dovecot configuration
cat > ./docker-data/config/dovecot.cf << EOF
ssl = yes
disable_plaintext_auth = no
mail_uid = 5000
mail_gid = 5000
EOF


podman run -d \
  --name mailserver \
  --hostname ${MAIL_HOSTNAME} \
  --network=netzor-network \
  -p 25:25 \
  -p 465:465 \
  -p 587:587 \
  -p 993:993 \
  -p 143:143 \
  -v ./docker-data/mail-data/:/var/mail:Z \
  -v ./docker-data/mail-state/:/var/mail-state/:Z \
  -v ./docker-data/mail-logs/:/var/log/mail/:Z \
  -v ./docker-data/config/:/tmp/docker-mailserver/:Z \
  -e ACCOUNT_PROVISIONER=LDAP \
  -e LDAP_SERVER_HOST=ldap://10.90.0.3 \
  -e LDAP_SEARCH_BASE="${IPA_SEARCH_BASE}" \
  -e LDAP_BIND_DN="${IPA_BIND_DN}" \
  -e LDAP_BIND_PW="${MAILSERVER_BIND_PASSWORD}" \
  -e LDAP_QUERY_FILTER_USER="(&(objectClass=inetOrgPerson)(mail=%s))" \
  -e LDAP_QUERY_FILTER_GROUP="(&(objectClass=groupOfNames)(mail=%s))" \
  -e LDAP_QUERY_FILTER_ALIAS="(&(objectClass=inetOrgPerson)(mail=%s))" \
  -e LDAP_QUERY_FILTER_DOMAIN="(|(&(mail=*@%s)(objectClass=inetOrgPerson))(&(mailGroupMember=*@%s)(objectClass=groupOfNames)))" \
  -e DOVECOT_PASS_FILTER="(&(objectClass=inetOrgPerson)(uid=%n))" \
  -e DOVECOT_USER_FILTER="(&(objectClass=inetOrgPerson)(uid=%n))" \
  -e DOVECOT_AUTH_BIND=yes \
  -e ENABLE_SASLAUTHD=1 \
  -e SASLAUTHD_MECHANISMS=ldap \
  -e SASLAUTHD_LDAP_SERVER=ldap://10.90.0.3 \
  -e SASLAUTHD_LDAP_BIND_DN="${IPA_BIND_DN}" \
  -e SASLAUTHD_LDAP_PASSWORD="${MAILSERVER_BIND_PASSWORD}" \
  -e SASLAUTHD_LDAP_SEARCH_BASE="${IPA_SEARCH_BASE}" \
  -e SASLAUTHD_LDAP_FILTER="(&(objectClass=inetOrgPerson)(uid=%U))" \
  -e POSTMASTER_ADDRESS=postmaster@${DOMAIN} \
  -e ENABLE_RSPAMD=1 \
  -e ENABLE_CLAMAV=1 \
  -e ENABLE_FAIL2BAN=1 \
  --cap-add NET_ADMIN \
  --restart=always \
  ghcr.io/docker-mailserver/docker-mailserver:15.1.0

echo "Mail Server started with hostname ${MAIL_HOSTNAME}"
echo "LDAP Integration configured with user: ${IPA_BIND_DN}"
