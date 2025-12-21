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
echo ""

# ===========================================
# Keycloak Configuration
# ===========================================

# Default values
DEFAULT_ADMIN_USER="admin"
DEFAULT_HOSTNAME="auth.netzor.pt"

# Prompt for Hostname
read -p "Enter Keycloak Hostname [${DEFAULT_HOSTNAME}]: " KEYCLOAK_HOSTNAME
KEYCLOAK_HOSTNAME=${KEYCLOAK_HOSTNAME:-$DEFAULT_HOSTNAME}

# Prompt for Admin User
read -p "Enter Keycloak Admin Username [${DEFAULT_ADMIN_USER}]: " KEYCLOAK_ADMIN
KEYCLOAK_ADMIN=${KEYCLOAK_ADMIN:-$DEFAULT_ADMIN_USER}

# Generate random passwords
KEYCLOAK_ADMIN_PASSWORD=$(openssl rand -hex 32)
DB_PASSWORD=$(openssl rand -hex 32)
DB_USER="keycloak"
DB_NAME="keycloak"

# FreeIPA Configuration Prompts
DEFAULT_IPA_REALM="netzor.pt"
read -p "Enter FreeIPA Realm [${DEFAULT_IPA_REALM}]: " IPA_REALM
IPA_REALM=${IPA_REALM:-$DEFAULT_IPA_REALM}

echo "Enter FreeIPA 'keycloak-bind' User Password (output from setup_freeipa.sh):"
read -s IPA_BIND_PASSWORD
echo ""

if [ -z "$IPA_BIND_PASSWORD" ]; then
    echo "ERROR: FreeIPA Bind Password is required!"
    exit 1
fi

# Calculate Base DN from Realm (e.g., netzor.pt -> dc=netzor,dc=pt)
IPA_BASE_DN="dc=$(echo $IPA_REALM | sed 's/\./,dc=/g')"
IPA_BIND_DN="uid=keycloak-bind,cn=users,cn=accounts,${IPA_BASE_DN}"
IPA_USERS_DN="cn=users,cn=accounts,${IPA_BASE_DN}"

echo ""
echo "FreeIPA Configuration:"
echo "  Realm: ${IPA_REALM}"
echo "  Base DN: ${IPA_BASE_DN}"
echo "  Bind DN: ${IPA_BIND_DN}"

echo ""
echo "Keycloak Configuration:"
echo "  Hostname: ${KEYCLOAK_HOSTNAME}"
echo "  Admin User: ${KEYCLOAK_ADMIN}"
echo "  Admin Password: ${KEYCLOAK_ADMIN_PASSWORD}"
echo "  Database User: ${DB_USER}"
echo "  Database Password: ${DB_PASSWORD}"
echo ""

# Confirm before proceeding
read -p "Press Enter to execute podman run..."

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
    echo "  Attempt ${RETRY_COUNT}/${MAX_RETRIES} - PostgreSQL is not ready yet..."
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
    echo "  Attempt ${RETRY_COUNT}/${MAX_RETRIES} - Keycloak is not ready yet..."
    sleep 5
done

echo "Keycloak is ready and authenticated!"

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
echo "Configuring FreeIPA LDAP User Federation..."

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
    
    echo "LDAP provider 'freeipa-ldap' configured successfully."
    
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

echo ""
echo "=================================================="
echo "Keycloak Setup Complete!"
echo "URL: https://${KEYCLOAK_HOSTNAME} (via BunkerWeb)"
echo "Admin Console: https://${KEYCLOAK_HOSTNAME}/admin"
echo "Admin User: ${KEYCLOAK_ADMIN}"
echo "Admin Password: ${KEYCLOAK_ADMIN_PASSWORD}"
echo "LDAP Integration: Active (Realm: ${IPA_REALM})"
echo "=================================================="