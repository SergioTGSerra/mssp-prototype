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

echo "FreeIPA is running."

# ===========================================
# Keycloak Configuration
# ===========================================

# Use environment variables from netzor.sh or defaults
KEYCLOAK_HOSTNAME="${NETZOR_KEYCLOAK_HOSTNAME:-auth.netzor.pt}"
IPA_REALM="${NETZOR_REALM:-netzor.pt}"
KEYCLOAK_ADMIN="admin"

# Generate random passwords
KEYCLOAK_ADMIN_PASSWORD=$(openssl rand -hex 32)
DB_PASSWORD=$(openssl rand -hex 32)
DB_USER="keycloak"
DB_NAME="keycloak"

# Generate random password for keycloak-bind system account
KEYCLOAK_BIND_PASSWORD=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9')
IPA_BIND_PASSWORD="${KEYCLOAK_BIND_PASSWORD}"

# ===========================================
# Create System Account in FreeIPA
# ===========================================
echo "Creating system account for Keycloak integration..."

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
    echo -e '${KEYCLOAK_BIND_PASSWORD}\n${KEYCLOAK_BIND_PASSWORD}' | ipa passwd keycloak-bind
    
    # Destroy Kerberos ticket
    kdestroy
"


# Calculate Base DN from Realm (e.g., netzor.pt -> dc=netzor,dc=pt)
IPA_BASE_DN="dc=$(echo $IPA_REALM | sed 's/\./,dc=/g')"
IPA_BIND_DN="uid=keycloak-bind,cn=users,cn=accounts,${IPA_BASE_DN}"
IPA_USERS_DN="cn=users,cn=accounts,${IPA_BASE_DN}"

# Save credentials to temp file for netzor.sh
if [ -n "$NETZOR_CREDENTIALS_FILE" ]; then
    cat >> "$NETZOR_CREDENTIALS_FILE" << EOF
KEYCLOAK_ADMIN_PASSWORD="${KEYCLOAK_ADMIN_PASSWORD}"
KEYCLOAK_BIND_PASSWORD="${KEYCLOAK_BIND_PASSWORD}"
EOF
fi

echo "Starting Keycloak setup..."

# 1. Start PostgreSQL
echo "Starting PostgreSQL..."
podman run --name postgres-keycloak -d \
    --network=netzor-network \
    --ip 10.90.0.5 \
    --dns=10.90.0.2 \
    -p 5432 \
    -e POSTGRES_DB=${DB_NAME} \
    -e POSTGRES_USER=${DB_USER} \
    -e POSTGRES_PASSWORD=${DB_PASSWORD} \
    -v postgres-keycloak:/var/lib/postgresql:Z \
    docker.io/library/postgres:18-alpine

# Wait for DB to be ready
echo "Waiting for PostgreSQL to be ready..."
MAX_RETRIES=30
RETRY_COUNT=0
until podman exec postgres-keycloak pg_isready -U ${DB_USER} -d ${DB_NAME} > /dev/null 2>&1; do
    RETRY_COUNT=$((RETRY_COUNT + 1))
    if [ $RETRY_COUNT -ge $MAX_RETRIES ]; then
        echo "ERROR: PostgreSQL failed to start after ${MAX_RETRIES} attempts."
        exit 1
    fi
    sleep 2
done
echo "PostgreSQL is ready!"

# 2. Start Keycloak (Production Mode)
echo "Starting Keycloak..."
podman run --name keycloak -d \
    --network=netzor-network \
    --ip 10.90.0.4 \
    --dns=10.90.0.2 \
    -p 8080 \
    -e KC_BOOTSTRAP_ADMIN_USERNAME=${KEYCLOAK_ADMIN} \
    -e KC_BOOTSTRAP_ADMIN_PASSWORD=${KEYCLOAK_ADMIN_PASSWORD} \
    -e KC_DB=postgres \
    -e KC_DB_URL=jdbc:postgresql://10.90.0.5:5432/${DB_NAME} \
    -e KC_DB_USERNAME=${DB_USER} \
    -e KC_DB_PASSWORD=${DB_PASSWORD} \
    -e KC_HOSTNAME=${KEYCLOAK_HOSTNAME} \
    -e KC_PROXY_HEADERS=xforwarded \
    -e KC_HTTP_ENABLED=true \
    quay.io/keycloak/keycloak:26.4.7 \
    start

# 3. Create 'netzor' realm
echo "Waiting for Keycloak to be ready..."
MAX_RETRIES=30
RETRY_COUNT=0
sleep 10 # Give it a head start

until podman exec keycloak /opt/keycloak/bin/kcadm.sh config credentials --server http://localhost:8080 --realm master --user ${KEYCLOAK_ADMIN} --password ${KEYCLOAK_ADMIN_PASSWORD} > /dev/null 2>&1; do
    RETRY_COUNT=$((RETRY_COUNT + 1))
    if [ $RETRY_COUNT -ge $MAX_RETRIES ]; then
        echo "ERROR: Keycloak failed to start/authenticate after ${MAX_RETRIES} attempts."
        exit 1
    fi
    sleep 5
done

echo "Keycloak is ready!"

echo "Creating 'netzor' realm..."
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

# 4. Configure FreeIPA LDAP User Federation
echo "Configuring FreeIPA LDAP integration..."

# Get the realm ID (needed for parentId)
REALM_ID=$(podman exec keycloak /opt/keycloak/bin/kcadm.sh get realms/netzor --fields id --format csv --noquotes 2>/dev/null | tail -1)

if [ -z "$REALM_ID" ]; then
    echo "ERROR: Could not get realm ID."
    exit 1
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
    -s "config.connectionUrl=[\"ldap://10.90.0.3\"]" \
    -s "config.usersDn=[\"${IPA_USERS_DN}\"]" \
    -s 'config.authType=["simple"]' \
    -s "config.bindDn=[\"${IPA_BIND_DN}\"]" \
    -s "config.bindCredential=[\"${IPA_BIND_PASSWORD}\"]" \
    -s 'config.searchScope=["1"]' \
    -s 'config.useTruststoreSpi=["ldapsOnly"]' \
    -s 'config.connectionPooling=["true"]' \
    -s 'config.pagination=["true"]' \
    -s 'config.allowKerberosAuthentication=["false"]' \
    -s 'config.useKerberosForPasswordAuthentication=["false"]' \
    -s 'config.customUserSearchFilter=["(!(|(uid=admin)(uid=keycloak-bind)))"]' \
    -s 'config.enabled=["true"]' \
    > /dev/null 2>&1; then
    
    echo "LDAP integration configured successfully."
    
    # Trigger sync
    echo "Triggering initial user sync..."
    LDAP_ID=$(podman exec keycloak /opt/keycloak/bin/kcadm.sh get components -r netzor --query providerType=org.keycloak.storage.UserStorageProvider --fields id --format csv --noquotes 2>/dev/null | tail -1)
    if [ -n "$LDAP_ID" ]; then
        podman exec keycloak /opt/keycloak/bin/kcadm.sh create user-storage/${LDAP_ID}/sync -r netzor -s action=triggerFullSync > /dev/null 2>&1 && \
            echo "User sync triggered." || echo "User sync may need to be triggered manually."
    fi

else
    echo "ERROR: Failed to configure LDAP provider."
    echo "Check if FreeIPA is reachable and password is correct."
fi

echo "Keycloak configuration complete."