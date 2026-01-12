#!/bin/bash
set -e

# Criar network se não existir
podman network exists waf || podman network create waf

WAF_DNS=$(podman network inspect waf --format '{{(index .Subnets 0).Gateway}}')

# Lista de serviços: HOSTNAME=BACKEND_URL
SERVICES=(
  "${FREEIPA_HOSTNAME}=https://freeipa"
  "${KEYCLOAK_HOSTNAME}=http://keycloak"
  "${ROUNDCUBE_HOSTNAME}=http://roundcube"
  "${NEXTCLOUD_HOSTNAME}=http://nextcloud"
  "${GLPI_HOSTNAME}=http://glpi"
  "${IRIS_HOSTNAME}=https://iriswebapp_nginx:8443"
  "${N8N_HOSTNAME}=http://n8n_app:5678"
  "${GUACAMOLE_HOSTNAME}=http://guacamole:8080"
)

# Variáveis dinâmicas do BunkerWeb
BUNKER_ENV=()

SERVER_NAMES=()

for SERVICE in "${SERVICES[@]}"; do
  HOST="${SERVICE%%=*}"
  BACKEND="${SERVICE#*=}"

  SERVER_NAMES+=("$HOST")

  BUNKER_ENV+=(
    -e "${HOST}_USE_REVERSE_PROXY=yes"
    -e "${HOST}_REVERSE_PROXY_HOST=${BACKEND}"
    -e "${HOST}_SECURITY_MODE=detect"
  )

  if [[ "$HOST" == "$KEYCLOAK_HOSTNAME" ]]; then
    BUNKER_ENV+=(-e "${HOST}_COOKIE_FLAGS=")
  fi
done

if podman container exists bunkerweb; then
  podman start bunkerweb
else
  podman run -d \
    --name bunkerweb \
    --network waf \
    --restart=always \
    -e DNS_RESOLVERS="${WAF_DNS}" \
    -p 80:8080/tcp \
    -p 443:8443/tcp \
    -p 443:8443/udp \
    -v bunkerweb:/data:Z \
    -e ADMIN_USERNAME="${BUNKERWEB_ADMIN_USERNAME}" \
    -e ADMIN_PASSWORD="${BUNKERWEB_ADMIN_PASSWORD}" \
    -e USE_CROWDSEC=yes \
    -e USE_WHITELIST=yes \
    -e WHITELIST_COUNTRY="PT" \
    -e WHITELIST_IP="10.0.0.0/8" \
    -e MULTISITE=yes \
    -e SERVER_NAME="${SERVER_NAMES[*]}" \
    "${BUNKER_ENV[@]}" \
    docker.io/bunkerity/bunkerweb-all-in-one:1.6.7
fi
