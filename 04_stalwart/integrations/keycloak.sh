# Create Keycloak OIDC Client for Mailserver
keycloak_create_oidc_client "mailserver" "${MAILSERVER_OIDC_CLIENT_SECRET}" \
    '["*"]' \
    '' \
    '{"oauth2.device.authorization.grant.enabled":"true","oidc.ciba.grant.enabled":"false"}' \
    "directAccessGrantsEnabled=true" \
    "serviceAccountsEnabled=true" \
    "standardFlowEnabled=true"