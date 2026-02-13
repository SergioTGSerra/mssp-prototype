#!/bin/bash
source utils.sh; script_init;

# Add keycloak-bind system user to FreeIPA
echo "Configuring FreeIPA Bind User..."
podman exec freeipa bash -c "
    echo '${FREEIPA_ADMIN_PASSWORD}' | kinit admin > /dev/null 2>&1

    if ! ipa user-show keycloak-bind > /dev/null 2>&1; then
        ipa user-add keycloak-bind \
            --first=Keycloak \
            --last=Bind \
            --cn='Keycloak Bind System Account' \
            --shell=/sbin/nologin
    fi

    ipa group-add-member system-accounts --users=keycloak-bind > /dev/null 2>&1 || true

    echo -e '${KEYCLOAK_LDAP_BIND_PASSWORD}\n${KEYCLOAK_LDAP_BIND_PASSWORD}' | ipa passwd keycloak-bind > /dev/null 2>&1
    
    kdestroy
"

# Start Keycloak with Podman Compose
echo "Starting Keycloak..."
cd "$(dirname "$0")"
PROJECT_NAME=$(basename "$PWD" | sed 's/^[0-9]*_//')
podman compose -p "$PROJECT_NAME" -f compose.yaml up -d

# Wait for Keycloak to be ready
MAX_RETRIES=60
RETRY_COUNT=0
until [[ "$(podman inspect --format='{{.State.Health.Status}}' keycloak)" == "healthy" ]] || [ $RETRY_COUNT -eq $MAX_RETRIES ]; do
    RETRY_COUNT=$((RETRY_COUNT + 1))
    if [ $RETRY_COUNT -ge $MAX_RETRIES ]; then
        echo "ERROR: Keycloak failed to become healthy after ${MAX_RETRIES} attempts."
        exit 1
    fi
    sleep 5
done

# Authenticate kcadm
echo "Authenticating Keycloak Admin..."
podman exec keycloak /opt/keycloak/bin/kcadm.sh config credentials --server http://"${KEYCLOAK_HOSTNAME}" --realm master --user "${KEYCLOAK_ADMIN_USERNAME}" --password "${KEYCLOAK_ADMIN_PASSWORD}"

# Create Realm
echo "Creating 'netzor' realm..."
if ! podman exec keycloak /opt/keycloak/bin/kcadm.sh get realms/netzor > /dev/null 2>&1; then
    podman exec keycloak /opt/keycloak/bin/kcadm.sh create realms -s realm=netzor -s enabled=true || {
        echo "ERROR: Failed to create 'netzor' realm."
        exit 1
    }
fi

# Create LDAP Provider
echo "Creating 'freeipa-ldap' provider..."
if ! podman exec keycloak /opt/keycloak/bin/kcadm.sh create components -r netzor \
    -s name="freeipa-ldap" \
    -s providerId=ldap \
    -s providerType=org.keycloak.storage.UserStorageProvider \
    -s 'config.priority=["0"]' \
    -s 'config.fullSyncPeriod=["-1"]' \
    -s 'config.changedSyncPeriod=["-1"]' \
    -s 'config.cachePolicy=["DEFAULT"]' \
    -s 'config.batchSizeForSync=["1000"]' \
    -s 'config.editMode=["READ_ONLY"]' \
    -s 'config.syncRegistrations=["false"]' \
    -s 'config.vendor=["FreeIPA"]' \
    -s 'config.usernameLDAPAttribute=["uid"]' \
    -s 'config.rdnLDAPAttribute=["uid"]' \
    -s 'config.uuidLDAPAttribute=["ipaUniqueID"]' \
    -s 'config.userObjectClasses=["inetOrgPerson, organizationalPerson"]' \
    -s "config.connectionUrl=[\"ldap://${FREEIPA_HOSTNAME}\"]" \
    -s "config.usersDn=[\"${FREEIPA_USER_DN}\"]" \
    -s 'config.authType=["simple"]' \
    -s "config.bindDn=[\"${KEYCLOAK_LDAP_BIND_DN}\"]" \
    -s "config.bindCredential=[\"${KEYCLOAK_LDAP_BIND_PASSWORD}\"]" \
    -s 'config.searchScope=["1"]' \
    -s 'config.useTruststoreSpi=["ldapsOnly"]' \
    -s 'config.connectionPooling=["true"]' \
    -s 'config.pagination=["true"]' \
    -s 'config.allowKerberosAuthentication=["false"]' \
    -s 'config.useKerberosForPasswordAuthentication=["false"]' \
    -s "config.customUserSearchFilter=[\"(!(|(uid=admin)(memberOf=cn=system-accounts,${FREEIPA_GROUP_DN})))\"]" \
    -s 'config.enabled=["true"]' \
    > /dev/null 2>&1; then
    
    # Check if failure is because it already exists (simplified check)
    # Ideally we would check before creating
    echo "LDAP provider might already exist or failed to create."
else    
    # Update Mapper
    LDAP_ID=$(podman exec keycloak /opt/keycloak/bin/kcadm.sh get components -r netzor -q name=freeipa-ldap | jq -r '.[0].id')
    MAPPER_ID=$(podman exec keycloak /opt/keycloak/bin/kcadm.sh get components -r netzor -q "name=first name" 2>/dev/null | jq -r ".[] | select(.parentId == \"${LDAP_ID}\") | .id")
    
    [[ -n "$MAPPER_ID" && "$MAPPER_ID" != "null" ]] && \
        podman exec keycloak /opt/keycloak/bin/kcadm.sh update components/${MAPPER_ID} -r netzor -s 'config."ldap.attribute"=["givenName"]' > /dev/null 2>&1 || \
        echo "ERROR: Failed to update LDAP mapper."

    # Create "Grupos-FreeIPA" mapper
    echo "Creating 'Grupos-FreeIPA' mapper..."
    GROUP_MAPPER_ID=$(podman exec keycloak /opt/keycloak/bin/kcadm.sh get components -r netzor -q "name=Grupos-FreeIPA" 2>/dev/null | jq -r ".[] | select(.parentId == \"${LDAP_ID}\") | .id")
    
    if [[ -z "$GROUP_MAPPER_ID" || "$GROUP_MAPPER_ID" == "null" ]]; then
        echo "Creating new Group Mapper..."
        podman exec keycloak /opt/keycloak/bin/kcadm.sh create components -r netzor \
            -s name="Grupos-FreeIPA" \
            -s providerId="group-ldap-mapper" \
            -s providerType="org.keycloak.storage.ldap.mappers.LDAPStorageMapper" \
            -s parentId="$LDAP_ID" \
            -s 'config."groups.dn"=["cn=groups,cn=accounts,dc=netzor,dc=pt"]' \
            -s 'config."group.name.ldap.attribute"=["cn"]' \
            -s 'config."group.object.classes"=["groupofnames, ipausergroup"]' \
            -s 'config."preserve.group.inheritance"=["true"]' \
            -s 'config."ignore.missing.groups"=["false"]' \
            -s 'config."membership.ldap.attribute"=["member"]' \
            -s 'config."membership.attribute.type"=["DN"]' \
            -s 'config."membership.user.ldap.attribute"=["member"]' \
            -s 'config."groups.ldap.filter"=["(objectclass=ipausergroup)"]' \
            -s 'config."mode"=["READ_ONLY"]' \
            -s 'config."user.roles.retrieve.strategy"=["GET_GROUPS_FROM_USER_MEMBEROF_ATTRIBUTE"]' \
            -s 'config."memberof.ldap.attribute"=["memberOf"]' \
            -s 'config."drop.non.existing.groups.during.sync"=["true"]' \
            -s 'config."groups.path"=["/"]' || echo "Failed to create Grupos-FreeIPA mapper"
    else
        echo "Grupos-FreeIPA mapper already exists."
    fi

fi
