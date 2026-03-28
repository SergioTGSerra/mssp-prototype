keycloak_create_oidc_client "${FRAPPE_OIDC_CLIENT_ID}" "${FRAPPE_OIDC_CLIENT_SECRET}" \
    "[\"https://${FRAPPE_HOSTNAME}/api/method/frappe.integrations.oauth2_logins.login_via_keycloak\"]" \
    "[\"https://${FRAPPE_HOSTNAME}\"]" \
    "{\"post.logout.redirect.uris\":\"https://${FRAPPE_HOSTNAME}/*\"}"
