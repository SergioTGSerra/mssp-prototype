#!/bin/bash

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
mkdir -p $(pwd)/data/postgres-keycloak-data && \
podman run --name postgres-keycloak -d \
    --network=netzor-network \
    -e POSTGRES_DB=${DB_NAME} \
    -e POSTGRES_USER=${DB_USER} \
    -e POSTGRES_PASSWORD=${DB_PASSWORD} \
    -v $(pwd)/data/postgres-keycloak-data:/var/lib/postgresql:Z \
    docker.io/library/postgres:18-alpine

# Wait for DB to be ready
echo "Waiting for Database to initialization..."
sleep 5

# 2. Start Keycloak (Production Mode)
echo "Starting Keycloak..."
podman run --name keycloak -d \
    --network=netzor-network \
    -p 8080:8080 \
    -e KEYCLOAK_ADMIN=${KEYCLOAK_ADMIN} \
    -e KEYCLOAK_ADMIN_PASSWORD=${KEYCLOAK_ADMIN_PASSWORD} \
    -e KC_DB=postgres \
    -e KC_DB_URL=jdbc:postgresql://postgres-keycloak:5432/${DB_NAME} \
    -e KC_DB_USERNAME=${DB_USER} \
    -e KC_DB_PASSWORD=${DB_PASSWORD} \
    -e KC_HOSTNAME=${KEYCLOAK_HOSTNAME} \
    -e KC_HTTP_ENABLED=true \
    quay.io/keycloak/keycloak:26.4.7 \
    start
