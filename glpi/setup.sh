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
    podman exec glpi php bin/console marketplace:download samlsso --no-interaction --force || {
        echo "Warning: Failed to download SAML plugin from Marketplace."
    }
    
    echo "Installing SAML plugin..."
    podman exec glpi php bin/console plugin:install samlsso --username=glpi --no-interaction || {
        echo "Warning: Failed to install SAML plugin."
    }
    
    echo "Activating SAML plugin..."
    podman exec glpi php bin/console plugin:activate samlsso --no-interaction || {
        echo "Warning: Failed to activate SAML plugin."
    }
    
    # Create Keycloak SAML client for GLPI
    echo "Creating Keycloak SAML client for GLPI (Hostname: ${GLPI_HOSTNAME})..."
    GLPI_CLIENT_ID="https://${GLPI_HOSTNAME}/"
    if podman exec keycloak /opt/keycloak/bin/kcadm.sh get clients -r netzor -q clientId="${GLPI_CLIENT_ID}" --fields clientId 2>/dev/null | grep -q "${GLPI_CLIENT_ID}"; then
        echo "GLPI SAML client already exists."
    else
        # Create client in a single command using JSON map for attributes to avoid Keycloak NPE
        podman exec keycloak /opt/keycloak/bin/kcadm.sh create clients -r netzor \
            -s clientId="${GLPI_CLIENT_ID}" \
            -s name="${GLPI_CLIENT_ID}" \
            -s enabled=true \
            -s protocol=saml \
            -s "rootUrl=https://${GLPI_HOSTNAME}" \
            -s "baseUrl=https://${GLPI_HOSTNAME}" \
            -s "redirectUris=[\"https://${GLPI_HOSTNAME}/*\"]" \
            -s 'attributes={"saml_force_post_binding":"true", "saml_name_id_format":"email", "saml.force.post.binding":"true", "saml.signature.algorithm":"RSA_SHA256"}' \
            -s frontchannelLogout=true \
             && echo "GLPI SAML client created successfully." || echo "Warning: Failed to create GLPI SAML client."
    fi
else
    echo "WARNING: GLPI_NETWORK_KEY not found. Skipping SAML plugin installation."
fi

echo "GLPI setup completed successfully!"