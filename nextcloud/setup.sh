#!/bin/bash

podman-compose -f $PWD/nextcloud/compose.yaml up -d

# 5. Configure Maintenance Window (4 AM to 8 AM)
#podman exec -u www-data nextcloud php occ config:system:set maintenance_window_start --value=4 --type=integer

# 6. Perform Mimetype Migrations
#podman exec -u www-data nextcloud php occ maintenance:repair --include-expensive

# 7. Add Missing Database Indices
#podman exec -u www-data nextcloud php occ db:add-missing-indices

# Wait for Nextcloud to be fully installed
echo ">> Waiting for Nextcloud to be fully installed (this may take a few minutes)..."
timeout=300
while [ $timeout -gt 0 ]; do
    if podman exec -u www-data nextcloud php occ status 2>/dev/null | grep -q "installed: true"; then
        echo ">> Nextcloud is installed and ready."
        break
    fi
    sleep 5
    timeout=$((timeout - 5))
done

if [ $timeout -le 0 ]; then
    echo ">> ERROR: Nextcloud installation did not complete within the timeout."
    exit 1
fi

# 8. Disable First Run Wizard and Enable Calendar/Mail Apps
echo ">> Configuring Nextcloud apps..."
podman exec -u www-data nextcloud php occ app:disable firstrunwizard
podman exec -u www-data nextcloud php occ app:install calendar || podman exec -u www-data nextcloud php occ app:enable calendar
podman exec -u www-data nextcloud php occ app:install mail || podman exec -u www-data nextcloud php occ app:enable mail
podman exec -u www-data nextcloud php occ app:install user_oidc || podman exec -u www-data nextcloud php occ app:enable user_oidc

# Create Nextcloud OIDC client
echo "Creating Nextcloud OIDC client..."
if podman exec keycloak /opt/keycloak/bin/kcadm.sh get clients -r netzor -q clientId=${NEXTCLOUD_OIDC_CLIENT_ID} --fields clientId 2>/dev/null | grep -q "${NEXTCLOUD_OIDC_CLIENT_ID}"; then
    echo "Nextcloud OIDC client already exists."
else
    if podman exec keycloak /opt/keycloak/bin/kcadm.sh create clients -r netzor \
        -s clientId="${NEXTCLOUD_OIDC_CLIENT_ID}" \
        -s enabled=true \
        -s clientAuthenticatorType=client-secret \
        -s secret="${NEXTCLOUD_OIDC_CLIENT_SECRET}" \
        -s "redirectUris=[\"https://${NEXTCLOUD_HOSTNAME}/apps/user_oidc/code\"]" \
        -s "webOrigins=[\"https://${NEXTCLOUD_HOSTNAME}\"]" \
        -s publicClient=false \
        -s protocol=openid-connect \
        -s 'defaultClientScopes=["openid", "profile", "email"]' \
        > /dev/null 2>&1; then
        echo "Nextcloud OIDC client created successfully."
    else
        echo "ERROR: Failed to create Nextcloud OIDC client."
    fi
fi

# Configure OIDC provider (Keycloak)
echo ">> Configuring Keycloak OIDC provider..."
podman exec -u www-data nextcloud php occ config:system:set allow_local_remote_servers --value=true --type=boolean
podman exec -u www-data nextcloud php occ config:app:set user_oidc httpclient.allowselfsigned --value=1

podman exec -u www-data nextcloud php occ user_oidc:provider keycloak \
    --clientid="${NEXTCLOUD_OIDC_CLIENT_ID}" \
    --clientsecret="${NEXTCLOUD_OIDC_CLIENT_SECRET}" \
    --discoveryuri="http://${KEYCLOAK_HOSTNAME}/realms/netzor/.well-known/openid-configuration"

echo ">> Nextcloud OIDC configuration complete."