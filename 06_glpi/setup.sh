#!/bin/bash
source utils.sh; script_init;

cd "$(dirname "$0")"
PROJECT_NAME=$(basename "$PWD" | sed 's/^[0-9]*_//')
podman compose -p "$PROJECT_NAME" -f compose.yaml up -d

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
    keycloak_create_saml_client \
        "${GLPI_CLIENT_ID}" \
        "[\"https://${GLPI_HOSTNAME}/*\"]" \
        "https://${GLPI_HOSTNAME}" \
        '{"saml_force_post_binding":"true", "saml_name_id_format":"email", "saml.force.post.binding":"true", "saml.signature.algorithm":"RSA_SHA256"}'

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
    podman exec glpi-db mariadb -u "${GLPI_DB_USER}" -p"${GLPI_DB_PASSWORD}" "${GLPI_DB_NAME}" -e "DELETE FROM glpi_plugin_samlsso_configs WHERE name='Keycloak';"
    podman exec -i glpi-db mariadb -u "${GLPI_DB_USER}" -p"${GLPI_DB_PASSWORD}" "${GLPI_DB_NAME}" <<EOF
INSERT INTO glpi_plugin_samlsso_configs (
    name, is_active, enforce_sso,
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
    'Keycloak', 1, 1,
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

    # Pre-provision master user with Super-Admin permissions (before SAML login)
    echo "Pre-provisioning master user '${MAIN_USER_USERNAME}@${DOMAIN}' with Super-Admin profile..."
    SAML_CONFIG_ID=$(podman exec glpi-db mariadb -u "${GLPI_DB_USER}" -p"${GLPI_DB_PASSWORD}" "${GLPI_DB_NAME}" -N -e "SELECT id FROM glpi_plugin_samlsso_configs WHERE name='Keycloak' LIMIT 1;")

    podman exec glpi-db mariadb -u "${GLPI_DB_USER}" -p"${GLPI_DB_PASSWORD}" "${GLPI_DB_NAME}" -e "
    INSERT INTO glpi_users (name, realname, firstname, authtype, auths_id, is_active, date_creation, date_mod)
    SELECT '${MAIN_USER_USERNAME}@${DOMAIN}', '${MAIN_USER_LASTNAME}', '${MAIN_USER_FIRSTNAME}', 4, ${SAML_CONFIG_ID:-1}, 1, NOW(), NOW()
    FROM DUAL
    WHERE NOT EXISTS (SELECT 1 FROM glpi_users WHERE name='${MAIN_USER_USERNAME}@${DOMAIN}');
    "

    MASTER_USER_ID=$(podman exec glpi-db mariadb -u "${GLPI_DB_USER}" -p"${GLPI_DB_PASSWORD}" "${GLPI_DB_NAME}" -N -e "SELECT id FROM glpi_users WHERE name='${MAIN_USER_USERNAME}@${DOMAIN}';")

    if [ ! -z "$MASTER_USER_ID" ]; then
        podman exec glpi-db mariadb -u "${GLPI_DB_USER}" -p"${GLPI_DB_PASSWORD}" "${GLPI_DB_NAME}" -e "
        INSERT INTO glpi_profiles_users (users_id, profiles_id, entities_id, is_recursive, is_dynamic)
        SELECT ${MASTER_USER_ID}, 4, 0, 1, 0
        FROM DUAL
        WHERE NOT EXISTS (SELECT 1 FROM glpi_profiles_users WHERE users_id=${MASTER_USER_ID} AND profiles_id=4);
        "
        echo "Master user '${MAIN_USER_USERNAME}@${DOMAIN}' pre-provisioned with Super-Admin profile successfully."
    else
        echo "Warning: Failed to pre-provision master user."
    fi

    # Deactivate default "Root" authorization rule and unset default profile
    # This ensures new users don't get 'Self-Service' in 'Root Entity' by default
    #podman exec glpi-db mariadb -u "${GLPI_DB_USER}" -p"${GLPI_DB_PASSWORD}" "${GLPI_DB_NAME}" -e "UPDATE glpi_rules SET is_active = 0 WHERE name = 'Root' AND sub_type = 'RuleRight';"
    echo "Disabling default authorization rules and profiles..."
    podman exec glpi-db mariadb -u "${GLPI_DB_USER}" -p"${GLPI_DB_PASSWORD}" "${GLPI_DB_NAME}" -e "UPDATE glpi_profiles SET is_default = 0 WHERE name = 'Self-Service';"

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