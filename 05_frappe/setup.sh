#!/bin/bash
source utils.sh; script_init;

cd "$(dirname "$0")"

APPS_JSON_BASE64=$(base64 -w 0 apps.json)
PROJECT_NAME=$(basename "$PWD" | sed 's/^[0-9]*_//')

if ! podman image exists frappe:16; then
  podman build \
   --build-arg=FRAPPE_PATH=https://github.com/frappe/frappe \
   --build-arg=FRAPPE_BRANCH=version-16 \
   --build-arg=APPS_JSON_BASE64=$APPS_JSON_BASE64 \
   --tag=frappe:16 \
   --file=images/layered/Containerfile .
fi

podman compose \
  --env-file .env \
  -p "$PROJECT_NAME" \
  -f compose.yaml \
  -f overrides/compose.mariadb.yaml \
  -f overrides/compose.redis.yaml \
  up -d

podman exec frappe-backend bench new-site erp.netzor.pt --admin-password=admin --db-root-password=123 --mariadb-user-host-login-scope='%' --install-app erpnext --install-app hrms
podman exec frappe-backend bench --site erp.netzor.pt set-config host_name "https://${FRAPPE_HOSTNAME}"

# ── Keycloak OIDC Client for Frappe/ERPNext ──────────────────────────────────

keycloak_create_oidc_client "${FRAPPE_OIDC_CLIENT_ID}" "${FRAPPE_OIDC_CLIENT_SECRET}" \
    "[\"https://${FRAPPE_HOSTNAME}/api/method/frappe.integrations.oauth2_logins.login_via_keycloak\"]" \
    "[\"https://${FRAPPE_HOSTNAME}\"]" \
    "{\"post.logout.redirect.uris\":\"https://${FRAPPE_HOSTNAME}/*\"}"

# ── Configure Frappe Social Login Key (Keycloak) ─────────────────────────────
echo ">> Configuring Frappe Social Login Key for Keycloak..."
podman exec frappe-backend bench --site erp.netzor.pt execute frappe.client.insert --kwargs "$(cat <<PYEOF
{
    "doc": {
        "doctype": "Social Login Key",
        "provider_name": "Keycloak",
        "enable_social_login": 1,
        "social_login_provider": "Keycloak",
        "client_id": "${FRAPPE_OIDC_CLIENT_ID}",
        "client_secret": "${FRAPPE_OIDC_CLIENT_SECRET}",
        "base_url": "https://${KEYCLOAK_HOSTNAME}/realms/netzor",
        "authorize_url": "https://${KEYCLOAK_HOSTNAME}/realms/netzor/protocol/openid-connect/auth",
        "access_token_url": "https://${KEYCLOAK_HOSTNAME}/realms/netzor/protocol/openid-connect/token",
        "redirect_url": "/api/method/frappe.integrations.oauth2_logins.login_via_keycloak",
        "api_endpoint": "https://${KEYCLOAK_HOSTNAME}/realms/netzor/protocol/openid-connect/userinfo",
        "auth_url_data": "{\"response_type\": \"code\", \"scope\": \"openid\"}",
        "custom_base_url": 1,
        "sign_ups": "Allow",
        "show_in_resource_metadata": 1
    }
}
PYEOF
)" 2>/dev/null && echo ">> Social Login Key configured successfully." || {
    # If already exists, update it instead
    echo ">> Social Login Key may already exist, attempting update..."
    podman exec frappe-backend bench --site erp.netzor.pt execute frappe.client.set_value --kwargs "$(cat <<PYEOF
{
    "doctype": "Social Login Key",
    "name": "Keycloak",
    "fieldname": {
        "enable_social_login": 1,
        "client_id": "${FRAPPE_OIDC_CLIENT_ID}",
        "client_secret": "${FRAPPE_OIDC_CLIENT_SECRET}",
        "base_url": "https://${KEYCLOAK_HOSTNAME}/realms/netzor",
        "authorize_url": "https://${KEYCLOAK_HOSTNAME}/realms/netzor/protocol/openid-connect/auth",
        "access_token_url": "https://${KEYCLOAK_HOSTNAME}/realms/netzor/protocol/openid-connect/token",
        "redirect_url": "/api/method/frappe.integrations.oauth2_logins.login_via_keycloak",
        "api_endpoint": "https://${KEYCLOAK_HOSTNAME}/realms/netzor/protocol/openid-connect/userinfo",
        "custom_base_url": 1,
        "sign_ups": "Allow"
    }
}
PYEOF
)" && echo ">> Social Login Key updated successfully." || echo ">> ERROR: Failed to configure Social Login Key."
}