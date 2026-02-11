#!/bin/bash
set -e

#Load env
set -a; source .env; set +a

# Criar network se não existir
podman network exists ipa_default || podman network create ipa_default

if podman container exists freeipa; then
  podman start freeipa
else
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

podman network connect waf_default freeipa

fi

# Wait for FreeIPA to be ready
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

# Add system-accounts group with no password expiry
podman exec freeipa bash -c "
    echo '${FREEIPA_ADMIN_PASSWORD}' | kinit admin
    ipa group-add system-accounts --desc='System Accounts (No Password Expiry)' || true
    ipa pwpolicy-add system-accounts --maxlife=0 --minlife=0 --history=0 --minclasses=0 --minlength=8 --priority=1 || true
    kdestroy
"

# FREEIPA DNS
    # -p 53:53/udp -p 53:53 \
    # --dns=127.0.0.1,1.1.1.1,8.8.8.8 \
    # --setup-dns \
    # --auto-forwarders \
    # --allow-zone-overlap