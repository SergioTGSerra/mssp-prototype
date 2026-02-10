#!/bin/bash
set -e

cd "$(dirname "$0")"

#Load env
set -a; source .env; set +a

PROJECT_NAME=$(basename "$PWD" | sed 's/^[0-9]*_//')
podman compose -p "$PROJECT_NAME" --env-file .env \
    -f compose.yaml \
    -f overrides/compose.mariadb.yaml \
    -f overrides/compose.redis.yaml \
    up -d


# podman exec frappe-backend bench new-site erp.netzor.pt --admin-password=admin --db-root-password=123 --install-app erpnext
# podman exec frappe-backend bench --site erp.netzor.pt set-config host_name "https://erp.netzor.pt"
# podman exec frappe-backend bench use erp.netzor.pt