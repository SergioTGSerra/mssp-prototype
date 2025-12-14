#!/bin/bash

# Netzor Infrastructure Manager - Sequential Setup

echo "=================================================="
echo "          Netzor Infrastructure Manager           "
echo "=================================================="

# 1. Setup Prerequisites (OpenSSL, Podman)
echo ">> Step 1: Checking/Installing Prerequisites..."
if [ -f "./setup_prerequisites.sh" ]; then
    ./setup_prerequisites.sh
    if [ $? -ne 0 ]; then
        echo "Error: Prerequisites setup failed. Exiting."
        exit 1
    fi
else
    echo "Error: setup_prerequisites.sh not found!"
    exit 1
fi

echo ""

# 2. Setup FreeIPA
echo ">> Step 2: Installing FreeIPA..."
if [ -f "./setup_freeipa.sh" ]; then
    ./setup_freeipa.sh
    if [ $? -ne 0 ]; then
        echo "Error: FreeIPA setup failed. Exiting."
        exit 1
    fi
else
    echo "Error: setup_freeipa.sh not found!"
    exit 1
fi


# 3. Setup Keycloak
echo ">> Step 3: Installing Keycloak..."
if [ -f "./setup_keycloak.sh" ]; then
    ./setup_keycloak.sh
    if [ $? -ne 0 ]; then
        echo "Error: Keycloak setup failed. Exiting."
        exit 1
    fi
else
    echo "Error: setup_keycloak.sh not found!"
    exit 1
fi

echo ""
echo "=================================================="
echo "          All operations completed.               "
echo "=================================================="
