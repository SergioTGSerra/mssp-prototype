#!/bin/bash
source utils.sh; script_init;

# Create jumpserver-bind system user in FreeIPA
freeipa_create_system_account "jumpserver-bind" "JumpServer" "Bind" "${JUMPSERVER_LDAP_BIND_PASSWORD}" "JumpServer Bind System Account"

# Criar networks se não existirem
podman network exists jumpserver_default || podman network create jumpserver_default

# Create volumes if they don't exist
podman volume exists jsdata || podman volume create jsdata
podman volume exists pgdata || podman volume create pgdata

if podman container exists jumpserver; then
  podman start jumpserver
else
  podman run --name jumpserver -d \
     --network=jumpserver_default \
     -e SECRET_KEY=PleaseChangeMe \
     -e BOOTSTRAP_TOKEN=PleaseChangeMe \
     -e AUTH_LDAP=true \
     -e AUTH_LDAP_SERVER_URI="ldap://${FREEIPA_HOSTNAME}" \
     -e AUTH_LDAP_BIND_DN="${JUMPSERVER_LDAP_BIND_DN}" \
     -e AUTH_LDAP_BIND_PASSWORD="${JUMPSERVER_LDAP_BIND_PASSWORD}" \
     -e AUTH_LDAP_SEARCH_OU="${FREEIPA_USER_DN}" \
     -e AUTH_LDAP_SEARCH_FILTER="(uid=%(user)s)" \
     -e AUTH_LDAP_USER_ATTR_MAP='{"username": "uid", "name": "cn", "email": "mail"}' \
     -v jsdata:/opt/data \
     -v pgdata:/var/lib/postgresql \
     --tmpfs /opt/download:rw \
     --tmpfs /var/log/nginx:rw \
     -p 2222:2222 \
     docker.io/jumpserver/jms_all:v4.10.15

  podman network connect waf_default jumpserver
fi
