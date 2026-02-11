#!/bin/bash

# Load env
set -a; source .env; set +a

# Criar networks se não existirem
podman network exists jumpserver-network || podman network create jumpserver-network

# Create volumes if they don't exist
podman volume exists jsdata || podman volume create jsdata
podman volume exists pgdata || podman volume create pgdata

if podman container exists jumpserver; then
  podman start jumpserver
else
  podman run --name jumpserver -d \
     --network=jumpserver-network \
     -e SECRET_KEY=PleaseChangeMe \
     -e BOOTSTRAP_TOKEN=PleaseChangeMe \
     -v jsdata:/opt/data \
     -v pgdata:/var/lib/postgresql \
     --tmpfs /opt/download:rw \
     --tmpfs /var/log/nginx:rw \
     -p 2222:2222 \
     docker.io/jumpserver/jms_all:v4.10.15

  podman network connect waf_default jumpserver
fi
