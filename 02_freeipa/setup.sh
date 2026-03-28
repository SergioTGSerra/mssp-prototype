#!/bin/bash
# Initialize utility scripts and common variables
source utils.sh; script_init;

# Create dedicated Podman network for FreeIPA if it doesn't already exist
podman network exists ipa_default || podman network create ipa_default

# Check if the freeipa container already exists
if podman container exists freeipa; then
    # If it exists, just start it
    podman start freeipa
else
    # If it doesn't exist, create and run a new FreeIPA server container
    podman run --name freeipa -d \
        --network=ipa_default \
        --restart=always \
        -h ${FREEIPA_HOSTNAME} --read-only \
        --tmpfs /run --tmpfs /tmp \
        -v freeipa:/data:Z \
        -p 389:389 -p 636:636 \
        -p 88:88 -p 464:464 \
        -p 88:88/udp -p 464:464/udp \
        -p 123:123/udp \
        --health-cmd="ipactl status || exit 1" \
        --health-interval=30s \
        --health-retries=5 \
        --health-timeout=30s \
        --health-start-period=600s \
        quay.io/freeipa/freeipa-server:almalinux-10 \
        ipa-server-install -U \
        --realm=${FREEIPA_REALM} \
        --admin-password=${FREEIPA_ADMIN_PASSWORD} \
        --ds-password=${FREEIPA_DS_PASSWORD} \
        --no-ntp 

    # Connect the container to the external WAF network as well
    podman network connect waf_default freeipa
fi

# Poll the container health status until it becomes 'healthy' or reaches max retries
# This ensures that subsequent configuration commands are only run once the server is fully ready
MAX_RETRIES=120
RETRY_COUNT=0
until [[ "$(podman inspect --format='{{.State.Health.Status}}' freeipa)" == "healthy" ]] || [ $RETRY_COUNT -eq $MAX_RETRIES ]; do
    RETRY_COUNT=$((RETRY_COUNT + 1))
    if [ $RETRY_COUNT -ge $MAX_RETRIES ]; then
        echo "ERROR: FreeIPA failed to become healthy after ${MAX_RETRIES} attempts."
        exit 1
    fi
    sleep 5
done

# Provision a system-accounts group with a custom password policy (no expiry)
# This is useful for service accounts that require persistent credentials
podman exec freeipa bash -c "
    echo '${FREEIPA_ADMIN_PASSWORD}' | kinit admin
    ipa group-add system-accounts --desc='System Accounts (No Password Expiry)' || true
    ipa pwpolicy-add system-accounts --maxlife=0 --minlife=0 --history=0 --minclasses=0 --minlength=8 --priority=1 || true
    kdestroy
"

# Create the primary administrative user and set their initial password
# Includes logic to bypass the mandatory password change on first login using kpasswd
podman exec freeipa bash -c "
    echo '${FREEIPA_ADMIN_PASSWORD}' | kinit admin
    echo '${MAIN_USER_PASSWORD}' | ipa user-add ${MAIN_USER_USERNAME} --first='${MAIN_USER_FIRSTNAME}' --last='${MAIN_USER_LASTNAME}' --password
    echo -e '${MAIN_USER_PASSWORD}\n${MAIN_USER_PASSWORD}\n${MAIN_USER_PASSWORD}' | kpasswd ${MAIN_USER_USERNAME}
    ipa group-add-member admins --users=${MAIN_USER_USERNAME}
    kdestroy
"

# Optional: Configure OAuth 2.0 with Keycloak as an External Identity Provider
# Currently commented out as it requires specific OIDC configurations
# podman exec freeipa bash -c "
#     echo '${FREEIPA_ADMIN_PASSWORD}' | kinit admin
#     echo '${FREEIPA_OIDC_CLIENT_SECRET}' | ipa idp-add keycloak \
#         --provider keycloak \
#         --client-id '${FREEIPA_OIDC_CLIENT_ID}' \
#         --secret \
#         --org netzor \
#         --base-url 'https://${KEYCLOAK_HOSTNAME}' || true
#     kdestroy
# "

# Optional: Additional ports and flags for FreeIPA DNS configuration
# Useful if FreeIPA is intended to manage its own DNS zones
# FREEIPA DNS
    # -p 53:53/udp -p 53:53 \
    # --dns=127.0.0.1,1.1.1.1,8.8.8.8 \
    # --setup-dns \
    # --auto-forwarders \
    # --allow-zone-overlap

load_external_integrations