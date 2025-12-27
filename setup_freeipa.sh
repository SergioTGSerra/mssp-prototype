#!/bin/bash

podman run --name freeipa -d \
    --network=netzor-network \
    --ip ${FREEIPA_IP} \
    -h ${FREEIPA_HOSTNAME} --read-only \
    -v freeipa:/data:Z \
    -p 53:53/udp -p 53:53 \
    -p 80 -p 443 \
    -p 389:389 -p 636:636 \
    -p 88:88 -p 464:464 \
    -p 88:88/udp -p 464:464/udp \
    -p 123:123/udp \
    quay.io/freeipa/freeipa-server:rocky-9 \
    ipa-server-install -U \
    --realm=${FREEIPA_REALM} \
    --admin-password=${FREEIPA_ADMIN_PASSWORD} \
    --ds-password=${FREEIPA_DS_PASSWORD} \
    --no-ntp 

MAX_RETRIES=60
RETRY_COUNT=0
# Wait for the configuration completion message in logs
until podman logs freeipa 2>&1 | grep -q "FreeIPA server configured." || [ $RETRY_COUNT -eq $MAX_RETRIES ]; do
    RETRY_COUNT=$((RETRY_COUNT + 1))
    sleep 10
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    echo "ERROR: FreeIPA failed to start/configure in time."
    exit 1
fi

# Add system-accounts group with no password expiry
podman exec freeipa bash -c "
    echo '${FREEIPA_ADMIN_PASSWORD}' | kinit admin
    ipa group-add system-accounts --desc='System Accounts (No Password Expiry)' || true
    ipa pwpolicy-add system-accounts --maxlife=0 --minlife=0 --history=0 --minclasses=0 --minlength=8 --priority=1 || true
    kdestroy
"

# FREEIPA DNS
    # --dns=127.0.0.1,1.1.1.1,8.8.8.8 \
    # --setup-dns \
    # --auto-forwarders \
    # --allow-zone-overlap