#!/bin/bash

# Use environment variables from netzor.sh or defaults
HOSTNAME="${NETZOR_IPA_HOSTNAME:-ipa.netzor.pt}"
REALM="${NETZOR_REALM:-netzor.pt}"

# Generate random passwords (alphanumeric only, 24 chars to avoid PKCS12 issues)
DS_PASSWORD=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9')
ADMIN_PASSWORD=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9')

echo "Starting FreeIPA setup..."

# Execute podman command
podman run --name freeipa -d \
    --network=netzor-network \
    --ip 10.90.0.3 \
    -h ${HOSTNAME} --read-only \
    -v freeipa:/data:Z \
    -p 53:53/udp -p 53:53 \
    -p 80 -p 443 \
    -p 389:389 -p 636:636 \
    -p 88:88 -p 464:464 \
    -p 88:88/udp -p 464:464/udp \
    -p 123:123/udp \
    --dns=127.0.0.1,1.1.1.1,8.8.8.8 \
    quay.io/freeipa/freeipa-server:rocky-9 \
    ipa-server-install -U \
    --realm=${REALM} \
    --ds-password=${DS_PASSWORD} \
    --admin-password=${ADMIN_PASSWORD} \
    --no-ntp \
    --setup-dns \
    --auto-forwarders \
    --allow-zone-overlap

echo "FreeIPA container started."
echo "Waiting for FreeIPA configuration to complete..."
echo "(This may take several minutes)"

# Start streaming logs in background
podman logs -f freeipa &
LOG_PID=$!

# Wait for the configuration message
until podman logs freeipa 2>&1 | grep -q "FreeIPA server configured."; do
    sleep 2
done

# Kill the background log streamer
kill $LOG_PID
wait $LOG_PID 2>/dev/null

echo "FreeIPA setup completed!"

# Generate random password for keycloak-bind system account
KEYCLOAK_BIND_PASSWORD=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9')

# Save credentials to temp file for netzor.sh
if [ -n "$NETZOR_CREDENTIALS_FILE" ]; then
    cat >> "$NETZOR_CREDENTIALS_FILE" << EOF
FREEIPA_ADMIN_PASSWORD="${ADMIN_PASSWORD}"
FREEIPA_DS_PASSWORD="${DS_PASSWORD}"
KEYCLOAK_BIND_PASSWORD="${KEYCLOAK_BIND_PASSWORD}"
EOF
fi

# Export for Keycloak script
export NETZOR_KEYCLOAK_BIND_PASSWORD="${KEYCLOAK_BIND_PASSWORD}"

# Create system account and configure password policy
echo "Creating system account for Keycloak integration..."
podman exec freeipa bash -c "
    # Authenticate as admin
    echo '${ADMIN_PASSWORD}' | kinit admin

    # Create system accounts group
    ipa group-add system-accounts --desc='System Accounts (No Password Expiry)' 2>/dev/null || true

    # Create password policy for the group (maxlife=0 means no expiry)
    ipa pwpolicy-add system-accounts --maxlife=0 --minlife=0 --history=0 --minclasses=0 --minlength=8 --priority=1 2>/dev/null || true

    # Create keycloak-bind system user
    ipa user-add keycloak-bind \
        --first=Keycloak \
        --last=Bind \
        --cn='Keycloak Bind System Account' \
        --shell=/sbin/nologin 2>/dev/null || true

    # Add user to system-accounts group (applies the no-expiry policy)
    ipa group-add-member system-accounts --users=keycloak-bind 2>/dev/null || true

    # Set password for keycloak-bind
    echo -e '${KEYCLOAK_BIND_PASSWORD}\n${KEYCLOAK_BIND_PASSWORD}' | ipa passwd keycloak-bind

    # Destroy Kerberos ticket
    kdestroy
"

echo "FreeIPA configuration complete."