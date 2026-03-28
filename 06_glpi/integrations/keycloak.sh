GLPI_CLIENT_ID="${GLPI_CLIENT_ID:-https://${GLPI_HOSTNAME}/}"

keycloak_create_saml_client \
    "${GLPI_CLIENT_ID}" \
    "[\"https://${GLPI_HOSTNAME}/*\"]" \
    "https://${GLPI_HOSTNAME}" \
        '{"saml_force_post_binding":"true", "saml_name_id_format":"email", "saml.force.post.binding":"true", "saml.signature.algorithm":"RSA_SHA256"}'