#!/bin/bash

#Load env
set -a; source .env; set +a

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

podman exec glpi php bin/console glpi:config:set url_base "https://${GLPI_HOSTNAME}" --no-interaction

# Register GLPI Network Key to enable Marketplace
if [ ! -z "$GLPI_NETWORK_KEY" ]; then
    echo "Configuring GLPI Network Key..."
    podman exec glpi php bin/console glpi:config:set glpinetwork_registration_key "$GLPI_NETWORK_KEY" --no-interaction
    
    echo "Downloading SAML plugin from Marketplace..."
    podman exec glpi php bin/console marketplace:download samlsso --no-interaction --force
    
    echo "Installing SAML plugin..."
    podman exec glpi php bin/console plugin:install samlsso --username=glpi --no-interaction
    
    echo "Activating SAML plugin..."
    podman exec glpi php bin/console plugin:activate samlsso --no-interaction
else
    echo "WARNING: GLPI_NETWORK_KEY not found. Skipping SAML plugin installation."
fi