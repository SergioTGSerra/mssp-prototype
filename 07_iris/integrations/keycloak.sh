keycloak_create_oidc_client "${IRIS_OIDC_CLIENT_ID}" "${IRIS_OIDC_CLIENT_SECRET}" \
    "[\"https://${IRIS_HOSTNAME}/oidc-authorize\"]" \
    "[\"https://${IRIS_HOSTNAME}\"]" \
    "{\"post.logout.redirect.uris\":\"https://${IRIS_HOSTNAME}/*\"}"