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

# Configuration logic moved from configurator container
DB_HOST=${DB_HOST:-db}
DB_PORT=${DB_PORT:-3306}
REDIS_CACHE=${REDIS_CACHE:-redis-cache:6379}
REDIS_QUEUE=${REDIS_QUEUE:-redis-queue:6379}
SOCKETIO_PORT=${SOCKETIO_PORT:-9000}

echo "Waiting for frappe-backend to be ready..."
until podman exec frappe-backend true 2>/dev/null; do
    sleep 1
done

echo "Configuring Frappe..."
podman exec frappe-backend bash -c "
    ls -1 apps > sites/apps.txt;
    bench set-config -g db_host $DB_HOST;
    bench set-config -gp db_port $DB_PORT;
    bench set-config -g redis_cache 'redis://$REDIS_CACHE';
    bench set-config -g redis_queue 'redis://$REDIS_QUEUE';
    bench set-config -g redis_socketio 'redis://$REDIS_QUEUE';
    bench set-config -gp socketio_port $SOCKETIO_PORT;
"

podman exec frappe-backend bench new-site erp.netzor.pt --admin-password=admin --db-root-password=123 --install-app erpnext
podman exec frappe-backend bench --site erp.netzor.pt set-config host_name "https://erp.netzor.pt"
podman exec frappe-backend bench use erp.netzor.pt