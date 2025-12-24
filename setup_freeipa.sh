#!/bin/bash

echo "Starting FreeIPA setup..."

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

# # Start streaming logs in background
# podman logs -f freeipa &
# LOG_PID=$!

# # Wait for the configuration message
# until podman logs freeipa 2>&1 | grep -q "FreeIPA server configured."; do
#     sleep 2
# done

# # Kill the background log streamer
# kill $LOG_PID
# wait $LOG_PID 2>/dev/null

# echo "FreeIPA setup completed!"

# # Save credentials to temp file for netzor.sh
# if [ -n "$NETZOR_CREDENTIALS_FILE" ]; then
#     cat >> "$NETZOR_CREDENTIALS_FILE" << EOF
# FREEIPA_ADMIN_PASSWORD="${ADMIN_PASSWORD}"
# FREEIPA_DS_PASSWORD="${DS_PASSWORD}"
# EOF
# fi

# FREEIPA DNS
# podman run --name freeipa -d \
#     --network=netzor-network \
#     --ip ${FREEIPA_IP} \
#     -h ${FREEIPA_HOSTNAME} --read-only \
#     -v freeipa:/data:Z \
#     -p 53:53/udp -p 53:53 \
#     -p 80 -p 443 \
#     -p 389:389 -p 636:636 \
#     -p 88:88 -p 464:464 \
#     -p 88:88/udp -p 464:464/udp \
#     -p 123:123/udp \
#     --dns=127.0.0.1,1.1.1.1,8.8.8.8 \
#     quay.io/freeipa/freeipa-server:rocky-9 \
#     ipa-server-install -U \
#     --realm=${FREEIPA_REALM} \
#     --admin-password=${FREEIPA_ADMIN_PASSWORD} \
#     --ds-password=${FREEIPA_DS_PASSWORD} \
#     --no-ntp \
#     --setup-dns \
#     --auto-forwarders \
#     --allow-zone-overlap