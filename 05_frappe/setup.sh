#!/bin/bash
set -e

#Load env
set -a; source .env; set +a

cd "$(dirname "$0")"

APPS_JSON_BASE64=$(base64 -w 0 apps.json)
PROJECT_NAME=$(basename "$PWD" | sed 's/^[0-9]*_//')

if ! podman image exists frappe:16; then
  podman build \
   --build-arg=FRAPPE_PATH=https://github.com/frappe/frappe \
   --build-arg=FRAPPE_BRANCH=version-16 \
   --build-arg=APPS_JSON_BASE64=$APPS_JSON_BASE64 \
   --tag=frappe:16 \
   --file=images/layered/Containerfile .
fi

podman compose \
  --env-file .env \
  -p "$PROJECT_NAME" \
  -f compose.yaml \
  -f overrides/compose.mariadb.yaml \
  -f overrides/compose.redis.yaml \
  up -d

podman exec frappe-backend bench new-site erp.netzor.pt --admin-password=admin --db-root-password=123 --install-app erpnext --install-app hrms
podman exec frappe-backend bench --site erp.netzor.pt set-config host_name "https://${FRAPPE_HOSTNAME}"