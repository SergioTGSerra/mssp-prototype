#!/bin/bash

#Load env
set -a; source .env; set +a

cd "$(dirname "$0")"
PROJECT_NAME=$(basename "$PWD" | sed 's/^[0-9]*_//')
podman compose -p "$PROJECT_NAME" -f compose.yaml --profile onlyoffice --profile talk --profile clamav --profile imaginary --profile fulltextsearch --profile whiteboard up -d

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
    if podman exec -u www-data nextcloud-aio-nextcloud php occ status 2>/dev/null | grep -q "installed: true"; then
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

# Disable First Run Wizard and Enable OIDC
echo ">> Configuring Nextcloud apps..."
podman exec -u www-data nextcloud-aio-nextcloud php occ app:disable firstrunwizard
podman exec -u www-data nextcloud-aio-nextcloud php occ app:install user_oidc || podman exec -u www-data nextcloud-aio-nextcloud php occ app:enable user_oidc

# Create Nextcloud OIDC client

keycloak_create_oidc_client "${NEXTCLOUD_OIDC_CLIENT_ID}" "${NEXTCLOUD_OIDC_CLIENT_SECRET}" \
    "[\"https://${NEXTCLOUD_HOSTNAME}/apps/user_oidc/code\", \"http://${NEXTCLOUD_HOSTNAME}/apps/user_oidc/code\"]" \
    "[\"https://${NEXTCLOUD_HOSTNAME}\", \"http://${NEXTCLOUD_HOSTNAME}\"]" \
    "{\"post.logout.redirect.uris\":\"https://${NEXTCLOUD_HOSTNAME}/*##http://${NEXTCLOUD_HOSTNAME}/*\"}"

# Set skeleton directory to empty string
podman exec -u www-data nextcloud-aio-nextcloud php occ config:system:set skeletondirectory --value=''
# Set allow_multiple_user_backends to false
podman exec -u www-data nextcloud-aio-nextcloud php occ config:app:set --type=string --value=0 user_oidc allow_multiple_user_backends

# # Configure OIDC provider (Keycloak)
# echo ">> Configuring Keycloak OIDC provider..."
podman exec -u www-data nextcloud-aio-nextcloud php occ config:system:set allow_local_remote_servers --value=true --type=boolean
podman exec -u www-data nextcloud-aio-nextcloud php occ config:app:set user_oidc httpclient.allowselfsigned --value=1
# Disable SSL verification for internal OIDC connections (staging/self-signed certs)
podman exec -u www-data nextcloud-aio-nextcloud php occ config:system:set curlconfig.ssl.verifypeer --value=false --type=boolean
podman exec -u www-data nextcloud-aio-nextcloud php occ config:system:set curlconfig.ssl.verifyhost --value=false --type=boolean

podman exec -u www-data nextcloud-aio-nextcloud php occ user_oidc:provider keycloak \
    --clientid="${NEXTCLOUD_OIDC_CLIENT_ID}" \
    --clientsecret="${NEXTCLOUD_OIDC_CLIENT_SECRET}" \
    --discoveryuri="https://${KEYCLOAK_HOSTNAME}/realms/netzor/.well-known/openid-configuration" 

# # Enable store_login_token for OIDC tokens
podman exec -u www-data nextcloud-aio-nextcloud php occ config:app:set user_oidc store_login_token --value=1

# Install mail_oidc_bridge app
echo ">> Installing mail_oidc_bridge app..."
podman cp apps/mail_oidc_bridge nextcloud-aio-nextcloud:/var/www/html/custom_apps/
podman exec nextcloud-aio-nextcloud chown -R www-data:www-data /var/www/html/custom_apps/mail_oidc_bridge
podman exec -u www-data nextcloud-aio-nextcloud php occ app:enable mail_oidc_bridge

# # Configure Mail provisioning (auto-creates mail accounts for users)
echo ">> Configuring Mail provisioning..."

# Wait for the Mail app to create its database tables
echo ">> Waiting for Mail app database tables..."
timeout=60
while [ $timeout -gt 0 ]; do
    if podman exec nextcloud-aio-database psql -U nextcloud -d nextcloud_database -c "\dt oc_mail_provisionings" 2>/dev/null | grep -q "oc_mail_provisionings"; then
        echo ">> Mail provisioning table ready."
        break
    fi
    sleep 2
    timeout=$((timeout - 2))
done

if [ $timeout -le 0 ]; then
    echo ">> WARNING: Mail provisioning table not found. Skipping provisioning config."
else
    podman exec nextcloud-aio-database psql -U nextcloud -d nextcloud_database -c "
    INSERT INTO oc_mail_provisionings (
        provisioning_domain, email_template, 
        imap_user, imap_host, imap_port, imap_ssl_mode,
        smtp_user, smtp_host, smtp_port, smtp_ssl_mode,
        sieve_enabled, ldap_aliases_provisioning, master_password_enabled
    ) VALUES (
        'netzor.pt', '%EMAIL%',
        '%EMAIL%', '${MAILSERVER_HOSTNAME}', 143, 'none',
        '%EMAIL%', '${MAILSERVER_HOSTNAME}', 587, 'none',
        false, false, false
    ) ON CONFLICT (provisioning_domain) DO NOTHING;
    "
    echo ">> Mail provisioning configured."
fi

# echo ">> Nextcloud OIDC and Mail configuration complete."