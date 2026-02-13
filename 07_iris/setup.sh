#!/bin/bash

# Load env
set -a; source .env; set +a

cd "$(dirname "$0")"
PROJECT_NAME=$(basename "$PWD" | sed 's/^[0-9]*_//')
podman compose -p "$PROJECT_NAME" -f compose.yaml up -d

# Create IRIS OIDC client

keycloak_create_oidc_client "${IRIS_OIDC_CLIENT_ID}" "${IRIS_OIDC_CLIENT_SECRET}" \
    "[\"https://${IRIS_HOSTNAME}/oidc-authorize\"]" \
    "[\"https://${IRIS_HOSTNAME}\"]" \
    "{\"post.logout.redirect.uris\":\"https://${IRIS_HOSTNAME}/*\"}"