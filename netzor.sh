#!/bin/bash

# Netzor Infrastructure Manager - Sequential Setup

echo "=================================================="
echo "          Netzor Infrastructure Manager           "
echo "=================================================="
echo ""

# Prompt for main domain (only user input required)
DEFAULT_DOMAIN="netzor.pt"
read -p "Enter your main domain [${DEFAULT_DOMAIN}]: " DOMAIN
DOMAIN=${DOMAIN:-$DEFAULT_DOMAIN}

# Export domain for all child scripts
export NETZOR_DOMAIN="${DOMAIN}"
export NETZOR_REALM="${DOMAIN}"
export NETZOR_IPA_HOSTNAME="ipa.${DOMAIN}"
export NETZOR_KEYCLOAK_HOSTNAME="auth.${DOMAIN}"

# Create temp file to store credentials
export NETZOR_CREDENTIALS_FILE=$(mktemp)

echo ""
echo "Starting infrastructure setup for domain: ${DOMAIN}"
echo ""

# 1. Setup Prerequisites (OpenSSL, Podman)
echo ">> Step 1: Checking/Installing Prerequisites..."
if [ -f "./setup_prerequisites.sh" ]; then
    ./setup_prerequisites.sh
    if [ $? -ne 0 ]; then
        echo "Error: Prerequisites setup failed. Exiting."
        rm -f "$NETZOR_CREDENTIALS_FILE"
        exit 1
    fi
else
    echo "Error: setup_prerequisites.sh not found!"
    rm -f "$NETZOR_CREDENTIALS_FILE"
    exit 1
fi

# 2. Setup BunkerWeb (WAF / Reverse Proxy)
echo ">> Step 2: Installing BunkerWeb (WAF)..."
if [ -f "./setup_bunkerweb.sh" ]; then
    chmod +x ./setup_bunkerweb.sh
    ./setup_bunkerweb.sh
    if [ $? -ne 0 ]; then
        echo "Error: BunkerWeb setup failed. Exiting."
        rm -f "$NETZOR_CREDENTIALS_FILE"
        exit 1
    fi
else
    echo "Error: setup_bunkerweb.sh not found!"
    rm -f "$NETZOR_CREDENTIALS_FILE"
    exit 1
fi

# 3. Setup FreeIPA
echo ">> Step 3: Installing FreeIPA..."
if [ -f "./setup_freeipa.sh" ]; then
    ./setup_freeipa.sh
    if [ $? -ne 0 ]; then
        echo "Error: FreeIPA setup failed. Exiting."
        rm -f "$NETZOR_CREDENTIALS_FILE"
        exit 1
    fi
else
    echo "Error: setup_freeipa.sh not found!"
    rm -f "$NETZOR_CREDENTIALS_FILE"
    exit 1
fi

# Source credentials from FreeIPA
source "$NETZOR_CREDENTIALS_FILE"

# 4. Setup Keycloak
echo ">> Step 4: Installing Keycloak..."
if [ -f "./setup_keycloak.sh" ]; then
    ./setup_keycloak.sh
    if [ $? -ne 0 ]; then
        echo "Error: Keycloak setup failed. Exiting."
        rm -f "$NETZOR_CREDENTIALS_FILE"
        exit 1
    fi
else
    echo "Error: setup_keycloak.sh not found!"
    rm -f "$NETZOR_CREDENTIALS_FILE"
    exit 1
fi

# Source all credentials
source "$NETZOR_CREDENTIALS_FILE"

echo ""
echo "=================================================="
echo "     NETZOR INFRASTRUCTURE SETUP COMPLETE         "
echo "=================================================="
echo ""
echo "Domain: ${NETZOR_DOMAIN}"
echo ""
echo "--------------------------------------------------"
echo "BunkerWeb (WAF/Reverse Proxy)"
echo "--------------------------------------------------"
echo "  Admin URL: https://${NETZOR_DOMAIN}:8443"
echo "  Username: admin"
echo "  Password: ChangeMe123!"
echo ""
echo "--------------------------------------------------"
echo "FreeIPA (Identity Management)"
echo "--------------------------------------------------"
echo "  URL: https://${NETZOR_IPA_HOSTNAME}"
echo "  Admin User: admin"
echo "  Admin Password: ${FREEIPA_ADMIN_PASSWORD}"
echo "  DS Password: ${FREEIPA_DS_PASSWORD}"
echo ""
echo "--------------------------------------------------"
echo "Keycloak (SSO/Authentication)"
echo "--------------------------------------------------"
echo "  URL: https://${NETZOR_KEYCLOAK_HOSTNAME}"
echo "  Admin Console: https://${NETZOR_KEYCLOAK_HOSTNAME}/admin"
echo "  Admin User: admin"
echo "  Admin Password: ${KEYCLOAK_ADMIN_PASSWORD}"
echo "  LDAP Integration: Active (Realm: ${NETZOR_REALM})"
echo ""
echo "--------------------------------------------------"
echo "FreeIPA <-> Keycloak Integration"
echo "--------------------------------------------------"
echo "  Bind User: keycloak-bind"
echo "  Bind Password: ${KEYCLOAK_BIND_PASSWORD}"
echo ""
echo "=================================================="

# Cleanup temp file
rm -f "$NETZOR_CREDENTIALS_FILE"
