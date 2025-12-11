#!/bin/bash

# Netzor Infrastructure Manager - Sequential Setup

echo "=================================================="
echo "          Netzor Infrastructure Manager           "
echo "=================================================="

# 1. Setup Podman
echo ">> Step 1: Checking/Installing Podman..."
if [ -f "./setup_podman.sh" ]; then
    ./setup_podman.sh
    if [ $? -ne 0 ]; then
        echo "Error: Podman setup failed. Exiting."
        exit 1
    fi
else
    echo "Error: setup_podman.sh not found!"
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

echo ""
echo "=================================================="
echo "          All operations completed.               "
echo "=================================================="
