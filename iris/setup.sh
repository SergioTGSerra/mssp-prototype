#!/bin/bash

# Load env
set -a; source .env; set +a

podman-compose -f $PWD/iris/compose.yaml up -d

# Create IRIS OIDC client
echo ">> Creating IRIS OIDC client..."
if podman exec keycloak /opt/keycloak/bin/kcadm.sh get clients -r netzor -q clientId=${IRIS_OIDC_CLIENT_ID} --fields clientId 2>/dev/null | grep -q "${IRIS_OIDC_CLIENT_ID}"; then
    echo ">> IRIS OIDC client already exists."
else
    if podman exec keycloak /opt/keycloak/bin/kcadm.sh create clients -r netzor \
        -s clientId="${IRIS_OIDC_CLIENT_ID}" \
        -s enabled=true \
        -s clientAuthenticatorType=client-secret \
        -s secret="${IRIS_OIDC_CLIENT_SECRET}" \
        -s "redirectUris=[\"https://${IRIS_HOSTNAME}/oidc-authorize\"]" \
        -s "attributes={\"post.logout.redirect.uris\":\"https://${IRIS_HOSTNAME}/*\"}" \
        -s "webOrigins=[\"https://${IRIS_HOSTNAME}\"]" \
        -s publicClient=false \
        -s protocol=openid-connect \
        -s 'defaultClientScopes=["profile", "openid", "email"]' \
        > /dev/null 2>&1; then
        echo ">> IRIS OIDC client created successfully."
    else
        echo ">> ERROR: Failed to create IRIS OIDC client."
    fi
fi