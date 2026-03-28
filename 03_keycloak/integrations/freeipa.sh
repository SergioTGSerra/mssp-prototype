# Add keycloak-bind system user to FreeIPA
freeipa_create_system_account "keycloak-bind" "Keycloak" "Bind" "${KEYCLOAK_LDAP_BIND_PASSWORD}" "Keycloak Bind System Account"