#!/bin/bash

podman network create waf

WAF_DNS=$(podman network inspect waf --format '{{(index .Subnets 0).Gateway}}')

podman run -d \
    --name bunkerweb \
    --network=waf \
    -e DNS_RESOLVERS="${WAF_DNS}" \
    -p 80:8080/tcp \
    -p 443:8443/tcp \
    -p 443:8443/udp \
    -v bunkerweb:/data:Z \
    -e ADMIN_USERNAME=${BUNKERWEB_ADMIN_USERNAME} \
    -e ADMIN_PASSWORD=${BUNKERWEB_ADMIN_PASSWORD} \
    -e USE_CROWDSEC=yes \
    -e USE_WHITELIST=yes \
    -e WHITELIST_COUNTRY="PT" \
    -e MULTISITE=yes \
    -e SERVER_NAME="${FREEIPA_HOSTNAME} ${KEYCLOAK_HOSTNAME} ${ROUNDCUBE_HOSTNAME} ${NEXTCLOUD_HOSTNAME} ${GLPI_HOSTNAME} ${IRIS_HOSTNAME}" \
    -e "${FREEIPA_HOSTNAME}_USE_REVERSE_PROXY=yes" \
    -e "${FREEIPA_HOSTNAME}_REVERSE_PROXY_HOST=https://freeipa" \
    -e "${FREEIPA_HOSTNAME}_SECURITY_MODE=detect" \
    -e "${KEYCLOAK_HOSTNAME}_USE_REVERSE_PROXY=yes" \
    -e "${KEYCLOAK_HOSTNAME}_REVERSE_PROXY_HOST=http://keycloak:8080" \
    -e "${KEYCLOAK_HOSTNAME}_SECURITY_MODE=detect" \
    -e "${ROUNDCUBE_HOSTNAME}_USE_REVERSE_PROXY=yes" \
    -e "${ROUNDCUBE_HOSTNAME}_REVERSE_PROXY_HOST=http://roundcube" \
    -e "${ROUNDCUBE_HOSTNAME}_SECURITY_MODE=detect" \
    -e "${NEXTCLOUD_HOSTNAME}_USE_REVERSE_PROXY=yes" \
    -e "${NEXTCLOUD_HOSTNAME}_REVERSE_PROXY_HOST=http://nextcloud-web" \
    -e "${NEXTCLOUD_HOSTNAME}_SECURITY_MODE=detect" \
    -e "${GLPI_HOSTNAME}_USE_REVERSE_PROXY=yes" \
    -e "${GLPI_HOSTNAME}_REVERSE_PROXY_HOST=http://glpi" \
    -e "${GLPI_HOSTNAME}_SECURITY_MODE=detect" \
    -e "${IRIS_HOSTNAME}_USE_REVERSE_PROXY=yes" \
    -e "${IRIS_HOSTNAME}_REVERSE_PROXY_HOST=https://iriswebapp_nginx:8443" \
    -e "${IRIS_HOSTNAME}_SECURITY_MODE=detect" \
    docker.io/bunkerity/bunkerweb-all-in-one:1.6.6
