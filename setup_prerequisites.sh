#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to detect OS
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        LIKE=$ID_LIKE
    else
        echo "Could not detect OS (/etc/os-release not found)."
        exit 1
    fi
}

# Function to install a package
install_package() {
    PACKAGE_NAME=$1
    if [[ "$OS" == "debian" || "$OS" == "ubuntu" || "$LIKE" == *"debian"* ]]; then
        CMD="sudo apt-get update && sudo apt-get install -y $PACKAGE_NAME"
    elif [[ "$OS" == "fedora" || "$OS" == "centos" || "$OS" == "rhel" || "$LIKE" == *"rhel"* || "$LIKE" == *"fedora"* ]]; then
        if command -v dnf &> /dev/null; then
            CMD="sudo dnf install -y $PACKAGE_NAME"
        else
            CMD="sudo yum install -y $PACKAGE_NAME"
        fi
    else
        echo "OS not automatically supported for installation."
        return 1
    fi

    echo -e "${GREEN}Installing $PACKAGE_NAME...${NC}"
    eval "$CMD"
}

detect_os

echo ">> Checking Podman..."
if command -v podman &> /dev/null; then
    echo -e "${GREEN}Podman is already installed!${NC}"
else
    echo -e "${RED}Podman not found. Installing...${NC}"
    install_package "podman"
    if [ $? -eq 0 ]; then
         echo -e "${GREEN}Podman installed successfully!${NC}"
    else
         echo -e "${RED}Failed to install Podman.${NC}"
         exit 1
    fi
fi

echo ""

NETWORK_NAME="netzor-network"
echo ">> Checking Podman Network '${NETWORK_NAME}'..."
if podman network exists ${NETWORK_NAME} 2>/dev/null; then
    echo -e "${GREEN}Network '${NETWORK_NAME}' already exists!${NC}"
else
    echo "Creating network '${NETWORK_NAME}' with DNS disabled..."
    podman network create --subnet 10.90.0.0/16 --gateway 10.90.0.1 --disable-dns ${NETWORK_NAME}
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Network '${NETWORK_NAME}' created successfully!${NC}"
    else
        echo -e "${RED}Failed to create network '${NETWORK_NAME}'.${NC}"
        exit 1
    fi
fi