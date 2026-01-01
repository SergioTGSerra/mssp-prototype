#!/bin/bash

podman run -d \
    --name glpi-db \
    --network=netzor-network \
    --ip ${GLPI_DB_IP} \
    -v glpi-db:/var/lib/mysql:Z \
    -e MYSQL_RANDOM_ROOT_PASSWORD="yes" \
    -e MYSQL_DATABASE=${GLPI_DB_NAME} \
    -e MYSQL_USER=${GLPI_DB_USER} \
    -e MYSQL_PASSWORD=${GLPI_DB_PASSWORD} \
    --health-cmd='mysqladmin ping -h 127.0.0.1 -u $MYSQL_USER --password=$MYSQL_PASSWORD' \
    --health-interval=5s \
    --health-retries=10 \
    --health-start-period=5s \
    --restart=unless-stopped \
    docker.io/library/mysql:9.5

# Wait for MariaDB to be healthy
MAX_RETRIES=30
RETRY_COUNT=0
until [ "$(podman inspect --format='{{.State.Health.Status}}' glpi-db)" == "healthy" ]; do
    RETRY_COUNT=$((RETRY_COUNT + 1))
    if [ $RETRY_COUNT -ge $MAX_RETRIES ]; then
        echo "ERROR: MariaDB failed to become healthy after ${MAX_RETRIES} attempts."
        exit 1
    fi
    sleep 5
done

podman run -d \
    --name glpi \
    --network=netzor-network \
    --ip ${GLPI_APP_IP} \
    -v glpi:/var/glpi:rw,Z \
    -e GLPI_DB_HOST=${GLPI_DB_IP} \
    -e GLPI_DB_PORT=3306 \
    -e GLPI_DB_NAME=${GLPI_DB_NAME} \
    -e GLPI_DB_USER=${GLPI_DB_USER} \
    -e GLPI_DB_PASSWORD=${GLPI_DB_PASSWORD} \
    --health-cmd='php bin/console system:status --allow-superuser' \
    --health-interval=10s \
    --health-retries=10 \
    --health-start-period=30s \
    --restart=unless-stopped \
    docker.io/glpi/glpi:11.0.4

# Wait for GLPI to be ready
MAX_RETRIES=30
RETRY_COUNT=0
until [ "$(podman inspect --format='{{.State.Health.Status}}' glpi)" == "healthy" ]; do
    RETRY_COUNT=$((RETRY_COUNT + 1))
    if [ $RETRY_COUNT -ge $MAX_RETRIES ]; then
        echo "ERROR: GLPI failed to become healthy after ${MAX_RETRIES} attempts."
        exit 1
    fi
    sleep 5
done