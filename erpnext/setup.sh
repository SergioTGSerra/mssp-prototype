#!/bin/bash
set -e

cd $PWD/erpnext

#Load env
set -a; source .env; set +a

podman-compose --env-file .env \
    -f compose.yaml \
    -f overrides/compose.mariadb.yaml \
    -f overrides/compose.redis.yaml \
    -f overrides/compose.noproxy.yaml \
    up -d