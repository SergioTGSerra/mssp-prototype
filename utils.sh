#!/bin/bash

# ── Common Utilities ──────────────────────────────────────────────────────────

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
