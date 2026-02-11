#!/bin/bash
set -e

cd "$(dirname "$0")"

#Load env
set -a; source .env; set +a

APPS_JSON_BASE64=$(base64 -w 0 apps.json)
PROJECT_NAME=$(basename "$PWD" | sed 's/^[0-9]*_//')

podman build \
 --build-arg=FRAPPE_PATH=https://github.com/frappe/frappe \
 --build-arg=FRAPPE_BRANCH=version-16 \
 --build-arg=APPS_JSON_BASE64=$APPS_JSON_BASE64 \
 --tag=custom:16 \
 --file=images/layered/Containerfile .

podman compose \
  --env-file .env \
  -p "$PROJECT_NAME" \
  -f compose.yaml \
  -f overrides/compose.mariadb.yaml \
  -f overrides/compose.redis.yaml \
  up -d