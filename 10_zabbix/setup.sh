#!/bin/bash
source utils.sh; script_init;

cd "$(dirname "$0")"
PROJECT_NAME=$(basename "$PWD" | sed 's/^[0-9]*_//')

CERTS_DIR="${PWD}/certs"
ZABBIX_SAML_SP_ENTITY_ID="${ZABBIX_SAML_SP_ENTITY_ID:-https://${ZABBIX_HOSTNAME}/}"
ZABBIX_SAML_IDP_ENTITY_ID="${ZABBIX_SAML_IDP_ENTITY_ID:-https://${KEYCLOAK_HOSTNAME}/realms/netzor}"
ZABBIX_SAML_SSO_URL="${ZABBIX_SAML_SSO_URL:-https://${KEYCLOAK_HOSTNAME}/realms/netzor/protocol/saml}"
ZABBIX_SAML_SLO_URL="${ZABBIX_SAML_SLO_URL:-https://${KEYCLOAK_HOSTNAME}/realms/netzor/protocol/saml}"
ZABBIX_API_URL="${ZABBIX_API_URL:-https://${ZABBIX_HOSTNAME}/api_jsonrpc.php}"
ZABBIX_ADMIN_USER="${ZABBIX_ADMIN_USER:-Admin}"
ZABBIX_ADMIN_PASSWORD="${ZABBIX_ADMIN_PASSWORD:-zabbix}"
ZABBIX_RESOLVE_TARGET="${ZABBIX_RESOLVE_TARGET:-127.0.0.1}"
ZABBIX_API_CONNECT_TIMEOUT="${ZABBIX_API_CONNECT_TIMEOUT:-10}"
ZABBIX_API_MAX_TIME="${ZABBIX_API_MAX_TIME:-60}"

ZABBIX_AUTH_TOKEN=""

# ── SP Certificate ────────────────────────────────────────────────────────────

prepare_zabbix_sp_certificate() {
    mkdir -p "${CERTS_DIR}"

    if [ -s "${CERTS_DIR}/sp.key" ] && [ -s "${CERTS_DIR}/sp.crt" ]; then
        echo ">> Reusing existing Zabbix SP certificate."
        return 0
    fi

    echo ">> Generating Zabbix SP certificate..."
    openssl req -x509 -newkey rsa:2048 \
        -keyout "${CERTS_DIR}/sp.key" \
        -out "${CERTS_DIR}/sp.crt" \
        -days 3650 \
        -nodes \
        -subj "/CN=${ZABBIX_HOSTNAME}" 2>/dev/null

    chmod 0644 "${CERTS_DIR}/sp.key" "${CERTS_DIR}/sp.crt"
}

# ── IdP Certificate ──────────────────────────────────────────────────────────

fetch_keycloak_idp_certificate() {
    echo ">> Fetching Keycloak SAML signing certificate..."
    local cert_content
    cert_content=$(podman exec keycloak /opt/keycloak/bin/kcadm.sh get keys -r netzor \
        | jq -r '.keys[] | select(.type == "RSA" and .use == "SIG") | .certificate' \
        | head -n 1)

    if [ -z "${cert_content}" ]; then
        echo "ERROR: Failed to obtain the Keycloak SAML signing certificate."
        exit 1
    fi

    cat > "${CERTS_DIR}/idp.crt" <<EOF
-----BEGIN CERTIFICATE-----
${cert_content}
-----END CERTIFICATE-----
EOF
    chmod 0644 "${CERTS_DIR}/idp.crt"
    echo ">> Keycloak IdP certificate stored in ${CERTS_DIR}/idp.crt."
}

# ── Keycloak SAML Client ─────────────────────────────────────────────────────

configure_keycloak_saml_client() {
    # Get client UUID
    local client_uuid
    client_uuid=$(podman exec keycloak /opt/keycloak/bin/kcadm.sh get clients -r netzor \
        -q clientId="${ZABBIX_SAML_SP_ENTITY_ID}" --fields id --format csv --noquotes)

    if [ -z "${client_uuid}" ]; then
        echo "ERROR: Failed to retrieve the Keycloak SAML client UUID for Zabbix."
        exit 1
    fi

    # Upload SP signing certificate to Keycloak
    local clean_sp_cert
    clean_sp_cert=$(grep -v 'BEGIN CERTIFICATE' "${CERTS_DIR}/sp.crt" | grep -v 'END CERTIFICATE' | tr -d '\r\n')

    if [ -n "${clean_sp_cert}" ]; then
        podman exec keycloak /opt/keycloak/bin/kcadm.sh update clients/"${client_uuid}" -r netzor \
            -s 'attributes."saml.client.signature"="true"' \
            -s 'attributes."saml.signing.certificate"="'"${clean_sp_cert}"'"' > /dev/null \
            && echo ">> Keycloak configured with Zabbix SP signing certificate." \
            || echo "WARNING: Failed to update Keycloak with SP signing certificate."
    fi

    # Remove all default client scopes to prevent duplicate SAML attributes
    echo ">> Removing default client scopes from Zabbix SAML client..."
    local scope_ids
    scope_ids=$(podman exec keycloak /opt/keycloak/bin/kcadm.sh get \
        clients/"${client_uuid}"/default-client-scopes -r netzor \
        | jq -r '.[].id' 2>/dev/null || true)

    for scope_id in ${scope_ids}; do
        podman exec keycloak /opt/keycloak/bin/kcadm.sh delete \
            clients/"${client_uuid}"/default-client-scopes/"${scope_id}" -r netzor 2>/dev/null || true
    done

    # Configure SAML protocol mappers (compact loop like GLPI)
    echo ">> Configuring SAML protocol mappers..."
    for mapper in username:username:username name:firstName:name surname:lastName:surname email:email:email; do
        local mapper_name mapper_attr mapper_saml
        mapper_name=$(echo "${mapper}" | cut -d: -f1)
        mapper_attr=$(echo "${mapper}" | cut -d: -f2)
        mapper_saml=$(echo "${mapper}" | cut -d: -f3)

        podman exec keycloak /opt/keycloak/bin/kcadm.sh create \
            clients/"${client_uuid}"/protocol-mappers/models -r netzor \
            -s "name=${mapper_name}" \
            -s "protocol=saml" \
            -s "protocolMapper=saml-user-property-mapper" \
            -s "consentRequired=false" \
            -s 'config."attribute.nameformat"="Basic"' \
            -s 'config."user.attribute"="'"${mapper_attr}"'"' \
            -s 'config."attribute.name"="'"${mapper_saml}"'"' \
            -s 'config."friendly.name"="'"${mapper_saml}"'"' 2>/dev/null || true
    done

    # Groups mapper
    podman exec keycloak /opt/keycloak/bin/kcadm.sh create \
        clients/"${client_uuid}"/protocol-mappers/models -r netzor \
        -s "name=groups" \
        -s "protocol=saml" \
        -s "protocolMapper=saml-group-membership-mapper" \
        -s "consentRequired=false" \
        -s 'config."attribute.nameformat"="Basic"' \
        -s 'config."attribute.name"="groups"' \
        -s 'config."friendly.name"="groups"' \
        -s 'config."single"="true"' \
        -s 'config."full.path"="false"' 2>/dev/null || true

    echo ">> Keycloak SAML client configured for Zabbix."
}

# ── Zabbix API ────────────────────────────────────────────────────────────────

zabbix_api_call() {
    local payload="$1"
    local response=""
    local method=""

    method=$(printf '%s' "${payload}" | jq -r '.method // "unknown"')
    echo ">> Zabbix API: ${method}" >&2

    response=$(curl -kfsS --resolve "${ZABBIX_HOSTNAME}:443:${ZABBIX_RESOLVE_TARGET}" \
        --connect-timeout "${ZABBIX_API_CONNECT_TIMEOUT}" \
        --max-time "${ZABBIX_API_MAX_TIME}" \
        -H 'Content-Type: application/json' \
        -H "Authorization: Bearer ${ZABBIX_AUTH_TOKEN}" \
        -d "${payload}" \
        "${ZABBIX_API_URL}")

    if ! printf '%s' "${response}" | jq -e . > /dev/null 2>&1; then
        echo "ERROR: Zabbix API returned a non-JSON response for method '${method}'." >&2
        printf '%s\n' "${response}" | sed -n '1,20p' >&2
        exit 1
    fi

    if printf '%s' "${response}" | jq -e '.error' > /dev/null; then
        echo "ERROR: Zabbix API call failed: $(printf '%s' "${response}" | jq -r '.error.data // .error.message')"
        exit 1
    fi

    printf '%s\n' "${response}"
}

zabbix_login() {
    local response=""
    local payload=""

    payload=$(jq -n \
        --arg username "${ZABBIX_ADMIN_USER}" \
        --arg password "${ZABBIX_ADMIN_PASSWORD}" \
        '{jsonrpc:"2.0", method:"user.login", params:{username:$username, password:$password}, id:1}')

    response=$(curl -kfsS --resolve "${ZABBIX_HOSTNAME}:443:${ZABBIX_RESOLVE_TARGET}" \
        --connect-timeout "${ZABBIX_API_CONNECT_TIMEOUT}" \
        --max-time "${ZABBIX_API_MAX_TIME}" \
        -H 'Content-Type: application/json' \
        -d "${payload}" \
        "${ZABBIX_API_URL}" 2>/dev/null || true)

    if [ -z "${response}" ] || ! printf '%s' "${response}" | jq -e . > /dev/null 2>&1; then
        return 1
    fi

    if ! printf '%s' "${response}" | jq -e '.result' > /dev/null 2>&1; then
        return 1
    fi

    ZABBIX_AUTH_TOKEN=$(printf '%s' "${response}" | jq -r '.result')
    [ -n "${ZABBIX_AUTH_TOKEN}" ]
}

# ── Zabbix SAML Configuration ────────────────────────────────────────────────

configure_zabbix_saml() {
    local login_retries=24

    echo ">> Authenticating to Zabbix API..."
    while [ "${login_retries}" -gt 0 ]; do
        if zabbix_login; then
            break
        fi
        login_retries=$((login_retries - 1))
        sleep 5
    done

    if [ -z "${ZABBIX_AUTH_TOKEN}" ]; then
        echo "WARNING: Failed to authenticate to the Zabbix API. Skipping SAML configuration."
        echo "WARNING: If SAML isn't configured, set ZABBIX_ADMIN_PASSWORD and rerun."
        return 0
    fi

    # Resolve role IDs
    local super_admin_role_id user_role_id email_mediatype_id

    super_admin_role_id=$(zabbix_api_call "$(jq -n \
        '{jsonrpc:"2.0", method:"role.get", params:{output:["roleid","name"], filter:{name:["Super admin role","Super admin"]}}, id:1}')" \
        | jq -r '.result[0].roleid // empty')

    user_role_id=$(zabbix_api_call "$(jq -n \
        '{jsonrpc:"2.0", method:"role.get", params:{output:["roleid","name"], filter:{name:["User role","User"]}}, id:1}')" \
        | jq -r '.result[0].roleid // empty')

    email_mediatype_id=$(zabbix_api_call "$(jq -n \
        '{jsonrpc:"2.0", method:"mediatype.get", params:{output:["mediatypeid","name","type"]}, id:1}')" \
        | jq -r '.result[] | select(.type == "0") | .mediatypeid' \
        | head -n 1)

    if [ -z "${super_admin_role_id}" ] || [ -z "${user_role_id}" ]; then
        echo "ERROR: Failed to resolve the default Zabbix role IDs."
        exit 1
    fi

    # Ensure user groups
    local admins_usrgrpid users_usrgrpid disabled_usrgrpid

    ensure_usergroup() {
        local group_name="$1" gui_access="${2:-0}" users_status="${3:-0}" group_id=""

        group_id=$(zabbix_api_call "$(jq -n --arg n "${group_name}" \
            '{jsonrpc:"2.0", method:"usergroup.get", params:{output:["usrgrpid","name"], filter:{name:[$n]}}, id:1}')" \
            | jq -r '.result[0].usrgrpid // empty')

        if [ -n "${group_id}" ]; then
            echo "${group_id}"
            return 0
        fi

        zabbix_api_call "$(jq -n --arg n "${group_name}" --argjson g "${gui_access}" --argjson s "${users_status}" \
            '{jsonrpc:"2.0", method:"usergroup.create", params:{name:$n, gui_access:$g, users_status:$s}, id:1}')" \
            | jq -r '.result.usrgrpids[0] // empty'
    }

    admins_usrgrpid=$(ensure_usergroup "SAML Zabbix Admins")
    users_usrgrpid=$(ensure_usergroup "SAML Zabbix Users")
    disabled_usrgrpid=$(ensure_usergroup "SAML Deprovisioned" 3 1)

    # Build SAML directory params
    local directory_params
    directory_params=$(jq -n \
        --arg idp_entityid "${ZABBIX_SAML_IDP_ENTITY_ID}" \
        --arg sp_entityid "${ZABBIX_SAML_SP_ENTITY_ID}" \
        --arg sso_url "${ZABBIX_SAML_SSO_URL}" \
        --arg slo_url "${ZABBIX_SAML_SLO_URL}" \
        --arg super_admin_role_id "${super_admin_role_id}" \
        --arg user_role_id "${user_role_id}" \
        --arg admins_usrgrpid "${admins_usrgrpid}" \
        --arg users_usrgrpid "${users_usrgrpid}" \
        --arg email_mediatype_id "${email_mediatype_id}" \
        '{
            idp_type: 2,
            name: "Keycloak SAML",
            description: "Keycloak SAML directory for Zabbix",
            provision_status: 1,
            group_name: "groups",
            user_username: "name",
            user_lastname: "surname",
            idp_entityid: $idp_entityid,
            sp_entityid: $sp_entityid,
            sso_url: $sso_url,
            slo_url: $slo_url,
            username_attribute: "username",
            nameid_format: "urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress",
            sign_messages: 1,
            sign_assertions: 1,
            sign_authn_requests: 1,
            sign_logout_requests: 1,
            sign_logout_responses: 1,
            provision_groups: [
                {
                    name: "admins",
                    roleid: $super_admin_role_id,
                    user_groups: [{ usrgrpid: $admins_usrgrpid }]
                },
                {
                    name: "*",
                    roleid: $user_role_id,
                    user_groups: [{ usrgrpid: $users_usrgrpid }]
                }
            ]
        } + (if $email_mediatype_id == "" then {} else {
            provision_media: [{
                name: "email",
                mediatypeid: $email_mediatype_id,
                attribute: "email"
            }]
        } end)')

    # Create or update SAML directory
    local saml_directory_id
    saml_directory_id=$(zabbix_api_call "$(jq -n \
        '{jsonrpc:"2.0", method:"userdirectory.get", params:{output:["userdirectoryid","idp_type"]}, id:1}')" \
        | jq -r '.result[] | select(.idp_type == "2") | .userdirectoryid' \
        | head -n 1)

    if [ -n "${saml_directory_id}" ]; then
        echo ">> Updating existing Zabbix SAML directory..."
        zabbix_api_call "$(jq -n \
            --argjson params "${directory_params}" \
            --arg id "${saml_directory_id}" \
            '{jsonrpc:"2.0", method:"userdirectory.update", params:($params + {userdirectoryid:$id}), id:1}')" > /dev/null
    else
        echo ">> Creating Zabbix SAML directory..."
        zabbix_api_call "$(jq -n \
            --argjson params "${directory_params}" \
            '{jsonrpc:"2.0", method:"userdirectory.create", params:$params, id:1}')" > /dev/null
    fi

    # Enable SAML authentication
    zabbix_api_call "$(jq -n \
        --arg disabled_usrgrpid "${disabled_usrgrpid}" \
        '{jsonrpc:"2.0", method:"authentication.update", params:{saml_auth_enabled:1, saml_jit_status:1, disabled_usrgrpid:$disabled_usrgrpid}, id:1}')" > /dev/null

    # Verify
    local auth_status saml_enabled saml_jit
    auth_status=$(zabbix_api_call "$(jq -n \
        '{jsonrpc:"2.0", method:"authentication.get", params:{output:["saml_auth_enabled","saml_jit_status"]}, id:1}')")
    saml_enabled=$(printf '%s' "${auth_status}" | jq -r '.result.saml_auth_enabled // empty')
    saml_jit=$(printf '%s' "${auth_status}" | jq -r '.result.saml_jit_status // empty')

    if [ "${saml_enabled}" != "1" ] || [ "${saml_jit}" != "1" ]; then
        echo "ERROR: Zabbix did not persist SAML settings (saml_auth_enabled='${saml_enabled}', saml_jit_status='${saml_jit}')."
        exit 1
    fi

    echo ">> Zabbix SAML authentication configured successfully."
}

# ── Main ──────────────────────────────────────────────────────────────────────

prepare_zabbix_sp_certificate
fetch_keycloak_idp_certificate

podman compose -p "${PROJECT_NAME}" -f compose.yaml up -d

# Wait for Zabbix to be ready
echo ">> Waiting for Zabbix to be ready..."
RETRIES=60
while ! curl -kfsS --resolve "${ZABBIX_HOSTNAME}:443:${ZABBIX_RESOLVE_TARGET}" \
    "https://${ZABBIX_HOSTNAME}/" > /dev/null 2>&1; do
    RETRIES=$((RETRIES - 1))
    if [ "${RETRIES}" -le 0 ]; then
        echo "ERROR: Zabbix did not become reachable."
        exit 1
    fi
    sleep 5
done

configure_keycloak_saml_client
configure_zabbix_saml
