#!/bin/bash
source utils.sh; script_init;

# Criar network se não existir
podman network exists waf_default || podman network create waf_default

WAF_GATEWAY=$(podman network inspect waf_default --format '{{(index .Subnets 0).Gateway}}')
WAF_SUBNET=$(podman network inspect waf_default --format '{{(index .Subnets 0).Subnet}}')

# Variáveis dinâmicas do BunkerWeb
BUNKER_ENV=()
SERVER_NAMES=()

# Diretório de configurações
CONFIG_DIR="$(dirname "$0")/configs"

echo "Loading configurations from $CONFIG_DIR..."

for config in "$CONFIG_DIR"/*.sh; do
  if [ -f "$config" ]; then
    echo "  - Sourcing $config"
    source "$config"
  fi
done

if podman container exists bunkerweb; then
  podman start bunkerweb
else
  podman run -d \
    --name bunkerweb \
    --network waf_default \
    -h ${BUNKERWEB_HOSTNAME} \
    --restart=always \
    -e DNS_RESOLVERS="${WAF_GATEWAY}" \
    -p 80:8080/tcp \
    -p 443:8443/tcp \
    -p 443:8443/udp \
    -v bunkerweb:/data:Z \
    -e ADMIN_USERNAME="${BUNKERWEB_ADMIN_USERNAME}" \
    -e ADMIN_PASSWORD="${BUNKERWEB_ADMIN_PASSWORD}" \
    -e USE_CROWDSEC=no \
    -e USE_WHITELIST=yes \
    -e WHITELIST_COUNTRY="PT" \
    -e WHITELIST_IP="10.0.0.0/8" \
    -e LETS_ENCRYPT_CHALLENGE=dns \
    -e LETS_ENCRYPT_DNS_PROVIDER=cloudflare \
    -e USE_LETS_ENCRYPT_WILDCARD=yes \
    -e USE_LETS_ENCRYPT_STAGING=no \
    -e AUTO_LETS_ENCRYPT=yes \
    -e LETS_ENCRYPT_DNS_CREDENTIAL_ITEM="${LETS_ENCRYPT_DNS_CREDENTIAL_ITEM}" \
    -e DISABLE_DEFAULT_SERVER=yes \
    -e DISABLE_DEFAULT_SERVER_STRICT_SNI=yes \
    -e USE_LIMIT_REQ=no \
    -e MULTISITE=yes \
    -e SERVER_NAME="${SERVER_NAMES[*]}" \
    "${BUNKER_ENV[@]}" \
    docker.io/bunkerity/bunkerweb-all-in-one:1.6.8
fi
