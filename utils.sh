#!/bin/bash

# ── Common Utilities ──────────────────────────────────────────────────────────

# Store the absolute path of the project root at the time this script is sourced.
# This ensures path resolution remains robust even if calling scripts use 'cd'.
export UTILS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Initialize script environment
# Sets exit on error (set -e).
# Loads the main .env (from project root) first, then overrides with local .env if present.
# Automatically exports all variables.
# Usage: script_init
script_init() {
    set -e
    set -a
    
    # Load root .env if it exists (when called from a subdirectory)
    if [ -f "../.env" ]; then
        source ../.env
    fi
    
    # Load local .env if it exists (overrides root .env)
    if [ -f ".env" ]; then
        source .env
    fi
    
    set +a
}

# ── Keycloak Utilities ────────────────────────────────────────────────────────

# Create an OIDC client in Keycloak (idempotent).
# Automatically authenticates with Keycloak Admin CLI using env vars.
#
# Usage:
#   keycloak_create_oidc_client <client_id> <client_secret> <redirect_uris> [web_origins] [attributes] [extra_args...]
#
# Arguments:
#   client_id      - The client ID (e.g. "erp", "nextcloud")
#   client_secret  - The client secret
#   redirect_uris  - JSON array string of redirect URIs (e.g. '["https://example.com/callback"]')
#   web_origins    - (optional) JSON array string of web origins (e.g. '["https://example.com"]')
#   attributes     - (optional) JSON object string of extra attributes (e.g. '{"post.logout.redirect.uris":"https://example.com/*"}')
#   extra_args...  - (optional) Additional -s flags to pass to kcadm.sh (e.g. "directAccessGrantsEnabled=true")
#
# Returns 0 on success (or if client already exists), 1 on error.
keycloak_create_oidc_client() {
    local client_id="$1"
    local client_secret="$2"
    local redirect_uris="$3"
    local web_origins="${4:-}"
    local attributes="${5:-}"
    shift 5 2>/dev/null || true

    if [ -z "$client_id" ] || [ -z "$client_secret" ] || [ -z "$redirect_uris" ]; then
        echo "ERROR: keycloak_create_oidc_client requires at least client_id, client_secret, and redirect_uris."
        return 1
    fi

    if ! podman inspect keycloak > /dev/null 2>&1; then
        echo "ERROR: Keycloak container not found. Cannot create client '${client_id}'."
        return 1
    fi

    # Authenticate (silent unless error)
    if ! podman exec keycloak /opt/keycloak/bin/kcadm.sh config credentials \
        --server http://"${KEYCLOAK_HOSTNAME}" \
        --realm master \
        --user "${KEYCLOAK_ADMIN_USERNAME}" \
        --password "${KEYCLOAK_ADMIN_PASSWORD}" > /dev/null 2>&1; then
        echo "ERROR: Failed to authenticate with Keycloak."
        return 1
    fi

    echo ">> Creating OIDC client '${client_id}' in Keycloak..."

    # Check if client already exists
    if podman exec keycloak /opt/keycloak/bin/kcadm.sh get clients -r netzor \
        -q clientId="${client_id}" --fields clientId 2>/dev/null | grep -q "${client_id}"; then
        echo ">> OIDC client '${client_id}' already exists."
        return 0
    fi

    # Build the create command
    local cmd=(
        podman exec keycloak /opt/keycloak/bin/kcadm.sh create clients -r netzor
        -s "clientId=${client_id}"
        -s "enabled=true"
        -s "clientAuthenticatorType=client-secret"
        -s "secret=${client_secret}"
        -s "redirectUris=${redirect_uris}"
        -s "publicClient=false"
        -s "protocol=openid-connect"
        -s 'defaultClientScopes=["profile", "openid", "email"]'
    )

    # Add optional web origins
    if [ -n "$web_origins" ]; then
        cmd+=(-s "webOrigins=${web_origins}")
    fi

    # Add optional attributes
    if [ -n "$attributes" ]; then
        cmd+=(-s "attributes=${attributes}")
    fi

    # Add any extra arguments
    for arg in "$@"; do
        cmd+=(-s "$arg")
    done

    if "${cmd[@]}" > /dev/null 2>&1; then
        echo ">> OIDC client '${client_id}' created successfully."
        return 0
    else
        echo ">> ERROR: Failed to create OIDC client '${client_id}'."
        return 1
    fi
}

# Create a SAML client in Keycloak (idempotent).
# Automatically authenticates with Keycloak Admin CLI using env vars.
#
# Usage:
#   keycloak_create_saml_client <client_id> <redirect_uris> [root_url] [attributes] [extra_args...]
#
# Arguments:
#   client_id      - The client ID / entity ID (e.g. "https://glpi.example.com/")
#   redirect_uris  - JSON array string of redirect URIs (e.g. '["https://example.com/*"]')
#   root_url       - (optional) Root URL for the client (e.g. "https://example.com")
#   attributes     - (optional) JSON object string of extra attributes
#                    (e.g. '{"saml_force_post_binding":"true", "saml_name_id_format":"email"}')
#   extra_args...  - (optional) Additional -s flags to pass to kcadm.sh
#
# Returns 0 on success (or if client already exists), 1 on error.
keycloak_create_saml_client() {
    local client_id="$1"
    local redirect_uris="$2"
    local root_url="${3:-}"
    local attributes="${4:-}"
    shift 4 2>/dev/null || true

    if [ -z "$client_id" ] || [ -z "$redirect_uris" ]; then
        echo "ERROR: keycloak_create_saml_client requires at least client_id and redirect_uris."
        return 1
    fi

    if ! podman inspect keycloak > /dev/null 2>&1; then
        echo "ERROR: Keycloak container not found. Cannot create SAML client '${client_id}'."
        return 1
    fi

    # Authenticate (silent unless error)
    if ! podman exec keycloak /opt/keycloak/bin/kcadm.sh config credentials \
        --server http://"${KEYCLOAK_HOSTNAME}" \
        --realm master \
        --user "${KEYCLOAK_ADMIN_USERNAME}" \
        --password "${KEYCLOAK_ADMIN_PASSWORD}" > /dev/null 2>&1; then
        echo "ERROR: Failed to authenticate with Keycloak."
        return 1
    fi

    echo ">> Creating SAML client '${client_id}' in Keycloak..."

    # Check if client already exists
    if podman exec keycloak /opt/keycloak/bin/kcadm.sh get clients -r netzor \
        -q clientId="${client_id}" --fields clientId 2>/dev/null | grep -q "${client_id}"; then
        echo ">> SAML client '${client_id}' already exists."
        return 0
    fi

    # Build the create command
    local cmd=(
        podman exec keycloak /opt/keycloak/bin/kcadm.sh create clients -r netzor
        -s "clientId=${client_id}"
        -s "name=${client_id}"
        -s "enabled=true"
        -s "protocol=saml"
        -s "redirectUris=${redirect_uris}"
        -s "frontchannelLogout=true"
    )

    # Add optional root URL and base URL
    if [ -n "$root_url" ]; then
        cmd+=(-s "rootUrl=${root_url}")
        cmd+=(-s "baseUrl=${root_url}")
    fi

    # Add optional attributes
    if [ -n "$attributes" ]; then
        cmd+=(-s "attributes=${attributes}")
    fi

    # Add any extra arguments
    for arg in "$@"; do
        cmd+=(-s "$arg")
    done

    if "${cmd[@]}" > /dev/null 2>&1; then
        echo ">> SAML client '${client_id}' created successfully."
        return 0
    else
        echo ">> ERROR: Failed to create SAML client '${client_id}'."
        return 1
    fi
}

# ── FreeIPA Utilities ─────────────────────────────────────────────────────────

# Create a system account in FreeIPA (idempotent).
# The user is created with /sbin/nologin shell and added to the system-accounts group.
#
# Usage:
#   freeipa_create_system_account <username> <first_name> <last_name> <password> [cn]
#
# Arguments:
#   username    - The username for the system account (e.g. "keycloak-bind")
#   first_name  - First name of the account (e.g. "Keycloak")
#   last_name   - Last name of the account (e.g. "Bind")
#   password    - Password for the system account
#   cn          - (optional) Custom common name (e.g. "Keycloak Bind System Account")
#
# Requires:
#   FREEIPA_ADMIN_PASSWORD - env var with admin password
#
# Returns 0 on success (or if user already exists), 1 on error.
freeipa_create_system_account() {
    local username="$1"
    local first_name="$2"
    local last_name="$3"
    local password="$4"
    local cn="${5:-}"

    if [ -z "$username" ] || [ -z "$first_name" ] || [ -z "$last_name" ] || [ -z "$password" ]; then
        echo "ERROR: freeipa_create_system_account requires at least username, first_name, last_name, and password."
        return 1
    fi

    if ! podman inspect freeipa > /dev/null 2>&1; then
        echo "ERROR: FreeIPA container not found. Cannot create system account '${username}'."
        return 1
    fi

    echo ">> Creating FreeIPA system account '${username}'..."

    local cn_flag=""
    if [ -n "$cn" ]; then
        cn_flag="--cn='${cn}'"
    fi

    podman exec freeipa bash -c "
        echo '${FREEIPA_ADMIN_PASSWORD}' | kinit admin > /dev/null 2>&1

        if ! ipa user-show ${username} > /dev/null 2>&1; then
            ipa user-add ${username} \
                --first='${first_name}' \
                --last='${last_name}' \
                ${cn_flag} \
                --shell=/sbin/nologin
        fi

        ipa group-add-member system-accounts --users=${username} > /dev/null 2>&1 || true
        ipa group-remove-member ipausers --users=${username} > /dev/null 2>&1 || true

        echo -e '${password}\n${password}' | ipa passwd ${username} > /dev/null 2>&1

        kdestroy
    "

    if [ $? -eq 0 ]; then
        echo ">> FreeIPA system account '${username}' configured successfully."
        return 0
    else
        echo ">> ERROR: Failed to configure FreeIPA system account '${username}'."
        return 1
    fi
}

# ── Execute Integrations ──────────────────────────────────────────────────────

# Run all integration scripts meant for the CURRENT service, 
# found in the 'integrations' folders of ALL other services.
#
# Usage: load_external_integrations
#
load_external_integrations() {
    # Determine the project directory (where utils.sh is located)
    local parent_dir="$UTILS_DIR"
    
    # Identify the script that called this function and extract its directory name
    local caller_script="${BASH_SOURCE[1]}"
    local caller_dir_name="$(basename "$(dirname "$caller_script")")"
    
    # Determine the name of the current service (e.g., "keycloak" from "03_keycloak")
    local service_name=$(echo "$caller_dir_name" | sed 's/^[0-9]*_//')

    echo ""
    echo "─────────────────────────────────────────────────────────────────"
    echo ">> Executing integrations for ${service_name} from other services..."
    echo "─────────────────────────────────────────────────────────────────"

    # Search for integration scripts targeting this service across all service folders
    for ext_config in "$parent_dir"/*/integrations/${service_name}.sh; do
        if [ -f "$ext_config" ]; then
            echo ">> Running integration: $ext_config"
            
            # Source the integration script so it inherits our utility functions and environment
            source "$ext_config"
            
            if [ $? -ne 0 ]; then
                echo ">> ERROR: Integration $ext_config failed."
                return 1
            fi
            
            echo ">> Completed: $ext_config"
            echo "-----------------------------------------------------------------"
        fi
    done

    echo ">> All integrations executed successfully."
    echo ""
}
