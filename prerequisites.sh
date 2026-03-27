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

    if [[ "$OS" == "fedora" || "$OS" == "centos" || "$OS" == "rhel" || "$LIKE" == *"rhel"* || "$LIKE" == *"fedora"* ]]; then
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

echo ">> Enabling and starting Podman socket..."
if systemctl is-active --quiet podman.socket; then
    echo -e "${GREEN}Podman socket is already active!${NC}"
else
    ${SUDO_CMD}systemctl enable podman.socket
    ${SUDO_CMD}systemctl start podman.socket
    echo -e "${GREEN}Podman socket activated successfully!${NC}"
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

echo ">> Checking curl..."
if command -v curl &> /dev/null; then
    echo -e "${GREEN}curl is already installed!${NC}"
else
    echo -e "${RED}curl not found. Installing...${NC}"
    install_package "curl"
    if [ $? -eq 0 ]; then
         echo -e "${GREEN}curl installed successfully!${NC}"
    else
         echo -e "${RED}Failed to install curl.${NC}"
         exit 1
    fi
fi

echo ">> Checking OpenSSL..."
if command -v openssl &> /dev/null; then
    echo -e "${GREEN}OpenSSL is already installed!${NC}"
else
    echo -e "${RED}OpenSSL not found. Installing...${NC}"
    install_package "openssl"
    if [ $? -eq 0 ]; then
         echo -e "${GREEN}OpenSSL installed successfully!${NC}"
    else
         echo -e "${RED}Failed to install OpenSSL.${NC}"
         exit 1
    fi
fi

echo ">> Checking docker-compose..."
if dnf list installed docker-compose-plugin &> /dev/null; then
    echo -e "${GREEN}docker compose já está instalado!${NC}"
else
    echo -e "${RED}docker-compose not found. Installing...${NC}"
    if [[ "$OS" == "fedora" || "$OS" == "centos" || "$OS" == "rhel" || "$LIKE" == *"rhel"* || "$LIKE" == *"fedora"* ]]; then
        sudo dnf install -y 'dnf-command(config-manager)'
        sudo dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo
        sudo dnf -y install docker-compose-plugin
    else
         echo "OS not automatically supported for docker-compose installation."
         exit 1
    fi
fi

echo ">> Configuring vm.overcommit_memory..."
if sysctl vm.overcommit_memory | grep -q '1'; then
    echo -e "${GREEN}vm.overcommit_memory is already set to 1!${NC}"
else
    echo -e "${RED}vm.overcommit_memory is not set to 1. Configuring...${NC}"
    if [ "$(id -u)" -eq 0 ]; then
        sysctl vm.overcommit_memory=1
        if grep -q "^vm.overcommit_memory" /etc/sysctl.conf; then
            sed -i 's/^vm.overcommit_memory.*/vm.overcommit_memory = 1/' /etc/sysctl.conf
        else
            echo "vm.overcommit_memory = 1" >> /etc/sysctl.conf
        fi
    else
        sudo sysctl vm.overcommit_memory=1
        if grep -q "^vm.overcommit_memory" /etc/sysctl.conf; then
            sudo sed -i 's/^vm.overcommit_memory.*/vm.overcommit_memory = 1/' /etc/sysctl.conf
        else
            echo "vm.overcommit_memory = 1" | sudo tee -a /etc/sysctl.conf > /dev/null
        fi
    fi
    echo -e "${GREEN}vm.overcommit_memory configured successfully!${NC}"
fi
