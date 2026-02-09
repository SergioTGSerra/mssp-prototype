#!/bin/bash

# Load env
set -a; source .env; set +a

# Criar networks se não existirem
podman network exists waf || podman network create waf
podman network exists jumpserver || podman network create jumpserver

podman volume create jsdata &> /dev/null
podman volume create pgdata &> /dev/null

if podman container exists jms_all; then
  podman start jms_all
else
  podman run --name jms_all -d \
     --network=jumpserver \
     -e SECRET_KEY=PleaseChangeMe \
     -e BOOTSTRAP_TOKEN=PleaseChangeMe \
     -v jsdata:/opt/data \
     -v pgdata:/var/lib/postgresql \
     -p 2222:2222 \
     docker.io/jumpserver/jms_all:v4.10.15

  podman network connect waf jms_all
fi
