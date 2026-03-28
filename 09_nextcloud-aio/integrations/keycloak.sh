keycloak_create_oidc_client "${NEXTCLOUD_OIDC_CLIENT_ID}" "${NEXTCLOUD_OIDC_CLIENT_SECRET}" \
    "[\"https://${NEXTCLOUD_HOSTNAME}/apps/user_oidc/code\", \"http://${NEXTCLOUD_HOSTNAME}/apps/user_oidc/code\"]" \
    "[\"https://${NEXTCLOUD_HOSTNAME}\", \"http://${NEXTCLOUD_HOSTNAME}\"]" \
    "{\"post.logout.redirect.uris\":\"https://${NEXTCLOUD_HOSTNAME}/*##http://${NEXTCLOUD_HOSTNAME}/*\"}"