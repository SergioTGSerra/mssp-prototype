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
    # Use sudo only if not running as root
    if [ "$(id -u)" -eq 0 ]; then
        SUDO_CMD=""
    else
        SUDO_CMD="sudo "
    fi

    if [[ "$OS" == "debian" || "$OS" == "ubuntu" || "$LIKE" == *"debian"* ]]; then
        CMD="${SUDO_CMD}apt-get update && ${SUDO_CMD}apt-get install -y $PACKAGE_NAME"
    elif [[ "$OS" == "fedora" || "$OS" == "centos" || "$OS" == "rhel" || "$LIKE" == *"rhel"* || "$LIKE" == *"fedora"* ]]; then
        if command -v dnf &> /dev/null; then
            CMD="${SUDO_CMD}dnf install -y $PACKAGE_NAME"
        else
            CMD="${SUDO_CMD}yum install -y $PACKAGE_NAME"
        fi
    else
        echo "OS not automatically supported for installation."
        return 1
    fi

    echo -e "${GREEN}Installing $PACKAGE_NAME...${NC}"
    eval "$CMD"
}

detect_os

echo ">> Checking sudo..."
if command -v sudo &> /dev/null; then
    echo -e "${GREEN}sudo is already installed!${NC}"
else
    echo -e "${RED}sudo not found. Installing...${NC}"
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${RED}Cannot install sudo without root access. Please run as root or install sudo manually.${NC}"
        exit 1
    fi
    install_package "sudo"
    if command -v sudo &> /dev/null; then
        echo -e "${GREEN}sudo installed successfully!${NC}"
    else
        echo -e "${RED}Failed to install sudo.${NC}"
        exit 1
    fi
fi

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

echo ">> Checking jq..."
if command -v jq &> /dev/null; then
    echo -e "${GREEN}jq is already installed!${NC}"
else
    echo -e "${RED}jq not found. Installing...${NC}"
    install_package "jq"
    if [ $? -eq 0 ]; then
         echo -e "${GREEN}jq installed successfully!${NC}"
    else
         echo -e "${RED}Failed to install jq.${NC}"
         exit 1
    fi
fi

echo ">> Checking podman-compose..."
if command -v podman-compose &> /dev/null; then
    echo -e "${GREEN}podman-compose is already installed!${NC}"
else
    echo -e "${RED}podman-compose not found. Installing...${NC}"
    if [[ "$OS" == "fedora" || "$OS" == "centos" || "$OS" == "rhel" || "$LIKE" == *"rhel"* || "$LIKE" == *"fedora"* ]]; then
        sudo dnf install -y 'dnf-command(config-manager)'
        sudo dnf config-manager --set-enabled crb
        sudo dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm
        sudo dnf install -y podman-compose
    elif [[ "$OS" == "debian" || "$OS" == "ubuntu" || "$LIKE" == *"debian"* ]]; then
        sudo apt-get update
        if apt-cache show podman-compose &> /dev/null; then
            sudo apt-get install -y podman-compose
        else
            echo -e "${RED}podman-compose not in apt repos, installing via pip...${NC}"
            sudo apt-get install -y python3-pip
            pip3 install podman-compose
        fi
    else
         echo "OS not automatically supported for podman-compose installation."
         exit 1
    fi
     
    if command -v podman-compose &> /dev/null; then
         echo -e "${GREEN}podman-compose installed successfully!${NC}"
    else
         echo -e "${RED}Failed to install podman-compose.${NC}"
         exit 1
    fi
fi