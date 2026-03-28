# Create jumpserver-bind system user in FreeIPA
freeipa_create_system_account "jumpserver-bind" "JumpServer" "Bind" "${JUMPSERVER_LDAP_BIND_PASSWORD}" "JumpServer Bind System Account"