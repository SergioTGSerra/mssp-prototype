#!/bin/bash

podman-compose -f $PWD/glpi/compose.yaml up -d

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

podman exec glpi php bin/console glpi:config:set --url_base=https://${GLPI_HOSTNAME} --allow-superuser