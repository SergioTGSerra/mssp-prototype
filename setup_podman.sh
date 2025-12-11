#!/bin/bash

# setup_podman.sh
# Script para verificar SO e instalar Podman se necessário

# Cores para output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}Verificando requisitos do sistema...${NC}"

# Verificar Podman
if command -v podman &> /dev/null; then
    echo -e "${GREEN}Podman já está instalado!${NC}"
    podman --version
    exit 0
fi

echo -e "${RED}Podman não encontrado.${NC}"

# Identificar Sistema Operativo
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    LIKE=$ID_LIKE
else
    echo "Não foi possível detetar o sistema operativo (/etc/os-release não encontrado)."
    exit 1
fi

echo "Sistema detetado: $PRETTY_NAME"

# Determinar gestor de pacotes e comando de instalação
INSTALL_CMD=""
if [[ "$OS" == "debian" || "$OS" == "ubuntu" || "$LIKE" == *"debian"* ]]; then
    INSTALL_CMD="sudo apt-get update && sudo apt-get install -y podman"
elif [[ "$OS" == "fedora" || "$OS" == "centos" || "$OS" == "rhel" || "$LIKE" == *"rhel"* || "$LIKE" == *"fedora"* ]]; then
    # Verificar se é dnf ou yum
    if command -v dnf &> /dev/null; then
        INSTALL_CMD="sudo dnf install -y podman"
    else
        INSTALL_CMD="sudo yum install -y podman"
    fi
else
    echo "Sistema operativo não suportado automaticamente por este script."
    echo "Por favor instale o Podman manualmente."
    exit 1
fi

# Pedir permissão ao utilizador
read -p "Deseja instalar o Podman agora? [S/n] " choice
case "$choice" in 
  y|Y|s|S|"" ) 
    echo -e "${GREEN}Iniciando instalação...${NC}"
    eval "$INSTALL_CMD"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Podman instalado com sucesso!${NC}"
        podman --version
    else
        echo -e "${RED}Falha na instalação do Podman.${NC}"
        exit 1
    fi
    ;;
  * ) 
    echo "Instalação cancelada pelo utilizador."
    exit 0
    ;;
esac
