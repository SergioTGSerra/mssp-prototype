#!/bin/bash
set -e

#Load env
set -a; source .env; set +a

# Criar network se não existir
podman network exists waf || podman network create waf

WAF_DNS=$(podman network inspect waf --format '{{(index .Subnets 0).Gateway}}')

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
    --network waf \
    -h ${BUNKERWEB_HOSTNAME} \
    --restart=always \
    -e DNS_RESOLVERS="${WAF_DNS}" \
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
    -e USE_LETS_ENCRYPT_STAGING=yes \
    -e AUTO_LETS_ENCRYPT=yes \
    -e LETS_ENCRYPT_DNS_CREDENTIAL_ITEM="${LETS_ENCRYPT_DNS_CREDENTIAL_ITEM}" \
    -e DISABLE_DEFAULT_SERVER=yes \
    -e DISABLE_DEFAULT_SERVER_STRICT_SNI=yes \
    -e MULTISITE=yes \
    -e SERVER_NAME="${SERVER_NAMES[*]}" \
    "${BUNKER_ENV[@]}" \
    docker.io/bunkerity/bunkerweb-all-in-one:1.6.8
fi
