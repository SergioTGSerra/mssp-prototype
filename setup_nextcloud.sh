#!/bin/bash

podman run -d \
    --name postgres-nextcloud \
    --network=netzor-network \
    --ip ${NEXTCLOUD_DB_IP} \
    -e POSTGRES_DB=${NEXTCLOUD_DB_NAME} \
    -e POSTGRES_USER=${NEXTCLOUD_DB_USER} \
    -e POSTGRES_PASSWORD=${NEXTCLOUD_DB_PASSWORD} \
    -v nextcloud-db:/var/lib/postgresql/data:Z \
    --restart=always \
    docker.io/library/postgres:17-alpine

# Wait for Postgres
echo "Waiting for PostgreSQL to be ready..."
MAX_RETRIES=30
RETRY_COUNT=0
until podman exec postgres-nextcloud pg_isready -U ${NEXTCLOUD_DB_USER} -d ${NEXTCLOUD_DB_NAME} > /dev/null 2>&1; do
    RETRY_COUNT=$((RETRY_COUNT + 1))
    if [ $RETRY_COUNT -ge $MAX_RETRIES ]; then
        echo "ERROR: PostgreSQL failed to start after ${MAX_RETRIES} attempts."
        exit 1
    fi
    sleep 2
done

podman run -d \
    --name redis-nextcloud \
    --network=netzor-network \
    --ip ${NEXTCLOUD_REDIS_IP} \
    -v nextcloud-redis-data:/data:Z \
    --restart=always \
    docker.io/library/redis:8.4-alpine redis-server --appendonly yes

podman run -d \
    --name nextcloud-app \
    --network=netzor-network \
    --ip ${NEXTCLOUD_APP_IP} \
    -e POSTGRES_HOST=${NEXTCLOUD_DB_IP} \
    -e POSTGRES_DB=${NEXTCLOUD_DB_NAME} \
    -e POSTGRES_USER=${NEXTCLOUD_DB_USER} \
    -e POSTGRES_PASSWORD=${NEXTCLOUD_DB_PASSWORD} \
    -e REDIS_HOST=${NEXTCLOUD_REDIS_IP} \
    -e NEXTCLOUD_ADMIN_USER=${NEXTCLOUD_ADMIN_USER} \
    -e NEXTCLOUD_ADMIN_PASSWORD=${NEXTCLOUD_ADMIN_PASSWORD} \
    -e NEXTCLOUD_TRUSTED_DOMAINS="${NEXTCLOUD_HOSTNAME} ${NEXTCLOUD_WEB_IP}" \
    -e TRUSTED_PROXIES="10.90.0.0/24" \
    -e OVERWRITEHOST=${NEXTCLOUD_HOSTNAME} \
    -e OVERWRITEPROTOCOL=https \
    -v nextcloud-data:/var/www/html:Z \
    -v nextcloud-config:/var/www/html/config:Z \
    --restart=always \
    docker.io/library/nextcloud:production-fpm-alpine

podman run -d \
    --name nextcloud-web \
    --network=netzor-network \
    --ip ${NEXTCLOUD_WEB_IP} \
    -p 8081:80 \
    -v $(pwd)/nginx_nextcloud.conf:/etc/nginx/nginx.conf:ro,Z \
    -v nextcloud-data:/var/www/html:ro,Z \
    --volumes-from nextcloud-app \
    --restart=always \
    docker.io/library/nginx:alpine