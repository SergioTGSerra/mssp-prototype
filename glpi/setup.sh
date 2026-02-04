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
    echo "Creating Keycloak SAML client for GLPI..."
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

    # Configure SAML Plugin in GLPI Database
    echo "Configuring SAML Plugin settings in database..."
    
    # Fetch Keycloak SAML Certificate using kcadm.sh (reliable internal method)
    CERT_CONTENT=$(podman exec keycloak /opt/keycloak/bin/kcadm.sh get keys -r netzor | jq -r '.keys[] | select(.type == "RSA" and .use == "SIG") | .certificate' | head -n 1)
    
    if [ ! -z "$CERT_CONTENT" ]; then
        KEYCLOAK_CERT="-----BEGIN CERTIFICATE-----
$CERT_CONTENT
-----END CERTIFICATE-----"
        echo "Fetched Keycloak SAML certificate."
    else
        KEYCLOAK_CERT=""
        echo "Warning: Could not fetch Keycloak SAML certificate via kcadm.sh."
    fi

    # Generate SP Certificate and Private Key if they don't exist in DB (or just generate new ones for setup)
    echo "Generating SP Certificate and Private Key for GLPI inside container..."
    podman exec glpi openssl req -x509 -newkey rsa:2048 -keyout /tmp/sp_key.pem -out /tmp/sp_cert.pem -days 3650 -nodes -subj "/CN=${GLPI_HOSTNAME}" 2>/dev/null
    
    # Certificate files are read directly in the configuration blocks below


    # Insert configuration using heredoc to handle multiline certificates safely
    echo "Configuring SAML Plugin settings in database (Clean setup)..."
    podman exec glpi-db mysql -u glpi -pglpi glpi -e "DELETE FROM glpi_plugin_samlsso_configs WHERE name='Keycloak';"
    podman exec -i glpi-db mysql -u glpi -pglpi glpi <<EOF
INSERT INTO glpi_plugin_samlsso_configs (
    name, is_active, 
    idp_entity_id, 
    idp_single_sign_on_service, 
    idp_single_logout_service,
    idp_certificate,
    user_jit,
    conf_icon,
    sp_certificate,
    sp_private_key,
    sp_nameid_format,
    requested_authn_context,
    requested_authn_context_comparison,
    compress_requests,
    compress_responses,
    proxied,
    strict,
    validate_xml,
    validate_destination,
    lowercase_url_encoding,
    security_authnrequestssigned,
    security_logoutrequestsigned,
    security_logoutresponsesigned,
    date_creation, date_mod
) VALUES (
    'Keycloak', 1,
    'https://${KEYCLOAK_HOSTNAME}/realms/netzor/protocol/saml',
    'https://${KEYCLOAK_HOSTNAME}/realms/netzor/protocol/saml',
    'https://${KEYCLOAK_HOSTNAME}/realms/netzor/protocol/saml',
    '$(echo -e "$KEYCLOAK_CERT")',
    1,
    'fa-solid fa-key',
    '$(podman exec glpi cat /tmp/sp_cert.pem)',
    '$(podman exec glpi cat /tmp/sp_key.pem)',
    'urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress',
    'urn:oasis:names:tc:SAML:2.0:ac:classes:PasswordProtectedTransport',
    'exact',
    1, 1, 1, 1, 1, 1, 1,
    1, 1, 1,
    NOW(), NOW()
);
EOF
    echo "SAML Plugin configured successfully."

    # Update Keycloak with SP Certificate for signature verification (Security Best Practice)
    echo "Updating Keycloak with GLPI SP signing certificate..."
    
    # Strip headers from SP cert for Keycloak config
    CLEAN_SP_CERT=$(podman exec glpi cat /tmp/sp_cert.pem | grep -v "BEGIN CERTIFICATE" | grep -v "END CERTIFICATE" | tr -d '\r\n')
    
    CLIENT_UUID=$(podman exec keycloak /opt/keycloak/bin/kcadm.sh get clients -r netzor -q clientId="${GLPI_CLIENT_ID}" --fields id --format csv --noquotes)
    
    if [ ! -z "$CLIENT_UUID" ] && [ ! -z "$CLEAN_SP_CERT" ]; then
         podman exec keycloak /opt/keycloak/bin/kcadm.sh update clients/${UUID_PART:-$CLIENT_UUID} -r netzor \
            -s 'attributes."saml.client.signature"="true"' \
            -s 'attributes."saml.signing.certificate"="'"$CLEAN_SP_CERT"'"' \
            && echo "Keycloak configured with GLPI signing certificate and signature verification ENABLED." || echo "Warning: Failed to update Keycloak with signing certificate."
            
         # Remove role_list scope to prevent duplicate 'Role' attributes error in GLPI
         SCOPE_ID=$(podman exec keycloak /opt/keycloak/bin/kcadm.sh get client-scopes -r netzor | jq -r '.[] | select(.name == "role_list") | .id')
         if [ ! -z "$SCOPE_ID" ]; then
             podman exec keycloak /opt/keycloak/bin/kcadm.sh delete clients/${CLIENT_UUID}/default-client-scopes/${SCOPE_ID} -r netzor 2>/dev/null || true
             echo "Removed 'role_list' scope from client."
         fi
         
         # Configure Explicit Mappers (username, email, firstname, realname)
         echo "Configuring SAML Protocol Mappers..."
         for MAPPER in username:username:username email:email:email firstname:firstName:firstname realname:lastName:realname; do
            NAME=$(echo $MAPPER | cut -d: -f1)
            ATTR=$(echo $MAPPER | cut -d: -f2)
            SAML_ATTR=$(echo $MAPPER | cut -d: -f3)
            
            podman exec keycloak /opt/keycloak/bin/kcadm.sh create clients/${CLIENT_UUID}/protocol-mappers/models -r netzor \
                -s name=$NAME \
                -s protocol=saml \
                -s protocolMapper=saml-user-property-mapper \
                -s consentRequired=false \
                -s 'config."attribute.nameformat"="Basic"' \
                -s 'config."user.attribute"="'"$ATTR"'"' \
                -s 'config."attribute.name"="'"$SAML_ATTR"'"' \
                -s 'config."friendly.name"="'"$SAML_ATTR"'"' 2>/dev/null || true
         done
    fi
else
    echo "WARNING: GLPI_NETWORK_KEY not found. Skipping SAML plugin installation."
fi

echo "GLPI setup completed successfully!"