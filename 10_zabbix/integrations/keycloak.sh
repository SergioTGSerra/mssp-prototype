ZABBIX_SAML_SP_ENTITY_ID="${ZABBIX_SAML_SP_ENTITY_ID:-https://${ZABBIX_HOSTNAME}/}"

keycloak_create_saml_client \
    "${ZABBIX_SAML_SP_ENTITY_ID}" \
    "[\"https://${ZABBIX_HOSTNAME}/index_sso.php*\", \"https://${ZABBIX_HOSTNAME}/\"]" \
    "https://${ZABBIX_HOSTNAME}" \
    '{"saml_force_post_binding":"true", "saml.force.post.binding":"true", "saml.client.signature":"true", "saml.server.signature":"true", "saml.assertion.signature":"true", "saml.signature.algorithm":"RSA_SHA256", "saml_name_id_format":"email"}'
