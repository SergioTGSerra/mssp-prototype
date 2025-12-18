#!/bin/bash

# ===========================================
# Check FreeIPA dependency
# ===========================================
echo "Checking FreeIPA dependency..."

# Check if FreeIPA container exists and is running
if ! podman ps --format "{{.Names}}" | grep -q "^freeipa$"; then
    echo "ERROR: FreeIPA container is not running!"
    echo "Please run setup_freeipa.sh first and wait for it to complete."
    exit 1
fi

# Use ldapsearch to verify LDAP is actually responding (anonymous bind to check base DN)
# We assume setup_freeipa.sh has already waited for configuration to complete.
echo "Verifying FreeIPA container status..."

if ! podman ps --format "{{.Names}}" | grep -q "^freeipa$"; then
    echo "ERROR: FreeIPA container is not running!"
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

echo "Configuration:"
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
    --ip 10.90.0.4 \
    --dns=10.90.0.2 \
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
    --ip 10.90.0.3 \
    --dns=10.90.0.2 \
    -p 8080:8080 \
    -e KC_BOOTSTRAP_ADMIN_USERNAME=${KEYCLOAK_ADMIN} \
    -e KC_BOOTSTRAP_ADMIN_PASSWORD=${KEYCLOAK_ADMIN_PASSWORD} \
    -e KC_DB=postgres \
    -e KC_DB_URL=jdbc:postgresql://10.90.0.4:5432/${DB_NAME} \
    -e KC_DB_USERNAME=${DB_USER} \
    -e KC_DB_PASSWORD=${DB_PASSWORD} \
    -e KC_HOSTNAME=${KEYCLOAK_HOSTNAME} \
    -e KC_PROXY_HEADERS=xforwarded \
    -e KC_HTTP_ENABLED=true \
    quay.io/keycloak/keycloak:26.4.7 \
    start
