#!/bin/bash

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

# Populate config volume with custom Dovecot configuration
podman volume create mailserver-config > /dev/null 2>&1
podman run --rm -v mailserver-config:/tmp/docker-mailserver:Z docker.io/library/busybox:latest sh -c "cat > /tmp/docker-mailserver/dovecot.cf << EOF
ssl = yes
disable_plaintext_auth = no
mail_uid = 5000
mail_gid = 5000
EOF"

podman run -d \
  --name mailserver \
  --hostname ${MAILSERVER_HOSTNAME} \
  --ip ${MAILSERVER_IP} \
  --network=netzor-network \
  -p 25:25 \
  -p 465:465 \
  -p 587:587 \
  -p 993:993 \
  -p 143:143 \
  -v mailserver-data:/var/mail:Z \
  -v mailserver-state:/var/mail-state/:Z \
  -v mailserver-logs:/var/log/mail/:Z \
  -v mailserver-config:/tmp/docker-mailserver:Z \
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
  -e ENABLE_SASLAUTHD=1 \
  -e SASLAUTHD_MECHANISMS=ldap \
  -e SASLAUTHD_LDAP_SERVER=ldap://${FREEIPA_IP} \
  -e SASLAUTHD_LDAP_BIND_DN="${MAILSERVER_LDAP_BIND_DN}" \
  -e SASLAUTHD_LDAP_PASSWORD="${MAILSERVER_LDAP_BIND_PASSWORD}" \
  -e SASLAUTHD_LDAP_SEARCH_BASE="cn=accounts,${FREEIPA_BASE_DN}" \
  -e SASLAUTHD_LDAP_FILTER="(&(objectClass=inetOrgPerson)(uid=%U)(!(|(uid=admin)(memberOf=cn=system-accounts,${FREEIPA_GROUP_DN}))))" \
  -e POSTMASTER_ADDRESS=postmaster@${FREEIPA_REALM} \
  -e ENABLE_RSPAMD=1 \
  -e ENABLE_CLAMAV=1 \
  -e ENABLE_FAIL2BAN=1 \
  --cap-add NET_ADMIN \
  --restart=always \
  ghcr.io/docker-mailserver/docker-mailserver:15.1.0