#!/bin/bash

# Default values
DEFAULT_HOSTNAME="ipa.netzor.pt"
DEFAULT_REALM="netzor.pt"

# Prompt for Hostname
read -p "Enter Hostname [${DEFAULT_HOSTNAME}]: " HOSTNAME
HOSTNAME=${HOSTNAME:-$DEFAULT_HOSTNAME}

# Prompt for Realm
read -p "Enter Realm [${DEFAULT_REALM}]: " REALM
REALM=${REALM:-$DEFAULT_REALM}

# Generate random passwords
DS_PASSWORD=$(openssl rand -hex 32)
ADMIN_PASSWORD=$(openssl rand -hex 32)

echo "Configuration:"
echo "  Hostname: ${HOSTNAME}"
echo "  Realm: ${REALM}"
echo "  DS Password: ${DS_PASSWORD}"
echo "  Admin Password: ${ADMIN_PASSWORD}"
echo ""

# Confirm before proceeding
read -p "Press Enter to execute podman run..."

# Execute podman command
mkdir -p $(pwd)/data/freeipa && \
podman run --name freeipa -d \
    -h ${HOSTNAME} --read-only \
    -v $(pwd)/data/freeipa:/data:Z \
    -p 53:53/udp -p 53:53 \
    -p 80:80 -p 443:443 \
    -p 389:389 -p 636:636 \
    -p 88:88 -p 464:464 \
    -p 88:88/udp -p 464:464/udp \
    -p 123:123/udp \
    --dns=127.0.0.1,1.1.1.1,8.8.8.8 \
    quay.io/freeipa/freeipa-server:rocky-9 \
    ipa-server-install -U \
    --realm=${REALM} \
    --ds-password=${DS_PASSWORD} \
    --admin-password=${ADMIN_PASSWORD} \
    --no-ntp \
    --setup-dns \
    --auto-forwarders \
    --allow-zone-overlap