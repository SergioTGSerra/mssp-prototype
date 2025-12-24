#!/bin/bash

if [ -z "$FREEIPA_ADMIN_PASSWORD" ]; then
    echo "WARNING: FREEIPA_ADMIN_PASSWORD not found."
    read -s -p "Enter FreeIPA 'admin' password: " FREEIPA_ADMIN_PASSWORD
    if [ -z "$FREEIPA_ADMIN_PASSWORD" ]; then
        echo "ERROR: Password is required to create system accounts."
        exit 1
    fi
fi

podman exec freeipa bash -c "
    # Authenticate as admin
    echo '${FREEIPA_ADMIN_PASSWORD}' | kinit admin

    # Create system accounts group (idempotent-ish check handled by || true)
    ipa group-add system-accounts --desc='System Accounts (No Password Expiry)' || true

    # Create password policy for the group (maxlife=0 means no expiry)
    ipa pwpolicy-add system-accounts --maxlife=0 --minlife=0 --history=0 --minclasses=0 --minlength=8 --priority=1 || true

    # Create keycloak-bind system user
    ipa user-add keycloak-bind \
        --first=Keycloak \
        --last=Bind \
        --cn='Keycloak Bind System Account' \
        --shell=/sbin/nologin || true

    # Add user to system-accounts group
    ipa group-add-member system-accounts --users=keycloak-bind || true

    # Set password
    echo -e '${KEYCLOAK_LDAP_BIND_PASSWORD}\n${KEYCLOAK_LDAP_BIND_PASSWORD}' | ipa passwd keycloak-bind
    
    # Destroy Kerberos ticket
    kdestroy
"

podman run --name postgres-keycloak -d \
    --network=netzor-network \
    --ip ${KEYCLOAK_DB_IP} \
    -p 5432 \
    -e POSTGRES_DB=${KEYCLOAK_DB_NAME} \
    -e POSTGRES_USER=${KEYCLOAK_DB_USER} \
    -e POSTGRES_PASSWORD=${KEYCLOAK_DB_PASSWORD} \
    -v postgres-keycloak:/var/lib/postgresql:Z \
    docker.io/library/postgres:18-alpine

MAX_RETRIES=30
RETRY_COUNT=0
until podman exec postgres-keycloak pg_isready -U ${KEYCLOAK_DB_USER} -d ${KEYCLOAK_DB_NAME} > /dev/null 2>&1; do
    RETRY_COUNT=$((RETRY_COUNT + 1))
    if [ $RETRY_COUNT -ge $MAX_RETRIES ]; then
        echo "ERROR: PostgreSQL failed to start after ${MAX_RETRIES} attempts."
        exit 1
    fi
    sleep 2
done

podman run --name keycloak -d \
    --network=netzor-network \
    --ip ${KEYCLOAK_IP} \
    -p 8080 \
    -e KC_BOOTSTRAP_ADMIN_USERNAME=${KEYCLOAK_ADMIN_USERNAME} \
    -e KC_BOOTSTRAP_ADMIN_PASSWORD=${KEYCLOAK_ADMIN_PASSWORD} \
    -e KC_DB=postgres \
    -e KC_DB_URL=jdbc:postgresql://${KEYCLOAK_DB_IP}:5432/${KEYCLOAK_DB_NAME} \
    -e KC_DB_USERNAME=${KEYCLOAK_DB_USER} \
    -e KC_DB_PASSWORD=${KEYCLOAK_DB_PASSWORD} \
    -e KC_HOSTNAME=${KEYCLOAK_HOSTNAME} \
    -e KC_PROXY_HEADERS=xforwarded \
    -e KC_HTTP_ENABLED=true \
    quay.io/keycloak/keycloak:26.4.7 \
    start

# Create 'netzor' realm
MAX_RETRIES=30
RETRY_COUNT=0

until podman exec keycloak /opt/keycloak/bin/kcadm.sh config credentials --server http://localhost:8080 --realm master --user ${KEYCLOAK_ADMIN} --password ${KEYCLOAK_ADMIN_PASSWORD} > /dev/null 2>&1; do
    RETRY_COUNT=$((RETRY_COUNT + 1))
    if [ $RETRY_COUNT -ge $MAX_RETRIES ]; then
        echo "ERROR: Keycloak failed to start/authenticate after ${MAX_RETRIES} attempts."
        exit 1
    fi
    sleep 5
done

if podman exec keycloak /opt/keycloak/bin/kcadm.sh get realms/netzor > /dev/null 2>&1; then
    echo "Realm 'netzor' already exists."
else
    if podman exec keycloak /opt/keycloak/bin/kcadm.sh create realms -s realm=netzor -s enabled=true; then
        echo "Realm 'netzor' created successfully."
    else
        echo "ERROR: Failed to create 'netzor' realm."
        exit 1
    fi
fi

if podman exec keycloak /opt/keycloak/bin/kcadm.sh create components -r netzor \
    -s name="freeipa-ldap" \
    -s providerId=ldap \
    -s providerType=org.keycloak.storage.UserStorageProvider \
    -s 'config.priority=["0"]' \
    -s 'config.fullSyncPeriod=["-1"]' \
    -s 'config.changedSyncPeriod=["-1"]' \
    -s 'config.cachePolicy=["DEFAULT"]' \
    -s 'config.batchSizeForSync=["1000"]' \
    -s 'config.editMode=["READ_ONLY"]' \
    -s 'config.syncRegistrations=["false"]' \
    -s 'config.vendor=["rhds"]' \
    -s 'config.usernameLDAPAttribute=["uid"]' \
    -s 'config.rdnLDAPAttribute=["uid"]' \
    -s 'config.uuidLDAPAttribute=["ipaUniqueID"]' \
    -s 'config.userObjectClasses=["inetOrgPerson, organizationalPerson"]' \
    -s "config.connectionUrl=[\"ldap://${FREEIPA_IP}\"]" \
    -s "config.usersDn=[\"${FREEIPA_USER_DN}\"]" \
    -s 'config.authType=["simple"]' \
    -s "config.bindDn=[\"${KEYCLOAK_LDAP_BIND_DN}\"]" \
    -s "config.bindCredential=[\"${KEYCLOAK_LDAP_BIND_PASSWORD}\"]" \
    -s 'config.searchScope=["1"]' \
    -s 'config.useTruststoreSpi=["ldapsOnly"]' \
    -s 'config.connectionPooling=["true"]' \
    -s 'config.pagination=["true"]' \
    -s 'config.allowKerberosAuthentication=["false"]' \
    -s 'config.useKerberosForPasswordAuthentication=["false"]' \
    -s "config.customUserSearchFilter=[\"(!(|(uid=admin)(memberOf=cn=system-accounts,cn=groups,cn=accounts,${FREEIPA_BASE_DN})))\"]" \
    -s 'config.enabled=["true"]' \
    > /dev/null 2>&1; then

else
    echo "ERROR: Failed to configure LDAP provider."
fi