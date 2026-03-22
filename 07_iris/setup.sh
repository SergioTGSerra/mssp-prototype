#!/bin/bash
source utils.sh; script_init;

cd "$(dirname "$0")"
PROJECT_NAME=$(basename "$PWD" | sed 's/^[0-9]*_//')
podman compose -p "$PROJECT_NAME" -f compose.yaml up -d

# Create IRIS OIDC client

keycloak_create_oidc_client "${IRIS_OIDC_CLIENT_ID}" "${IRIS_OIDC_CLIENT_SECRET}" \
    "[\"https://${IRIS_HOSTNAME}/oidc-authorize\"]" \
    "[\"https://${IRIS_HOSTNAME}\"]" \
    "{\"post.logout.redirect.uris\":\"https://${IRIS_HOSTNAME}/*\"}"

# Grant admin permissions to MAIN_USER
# Pre-creates the user in the DB so that on first OAuth login,
# the user already has Administrator group membership.

echo ">> Waiting for IRIS to initialize the database..."
sleep 30

echo ">> Granting admin permissions to '${MAIN_USER_USERNAME}' in IRIS..."
podman exec iriswebapp_db psql -U postgres -d iris_db -c "
  INSERT INTO \"user\" (\"user\", name, email, password, active)
  VALUES ('${MAIN_USER_USERNAME}', '${MAIN_USER_FIRSTNAME} ${MAIN_USER_LASTNAME}', '${MAIN_USER_USERNAME}@${DOMAIN}', '', true)
  ON CONFLICT (\"user\") DO NOTHING;

  INSERT INTO user_group (user_id, group_id)
  SELECT u.id, g.group_id
  FROM \"user\" u, groups g
  WHERE u.\"user\" = '${MAIN_USER_USERNAME}' AND g.group_name = 'Administrators'
  AND NOT EXISTS (
    SELECT 1 FROM user_group ug WHERE ug.user_id = u.id AND ug.group_id = g.group_id
  );

  INSERT INTO user_organisation (user_id, org_id, is_primary_org)
  SELECT u.id, 1, true
  FROM \"user\" u
  WHERE u.\"user\" = '${MAIN_USER_USERNAME}'
  AND NOT EXISTS (
    SELECT 1 FROM user_organisation uo WHERE uo.user_id = u.id AND uo.org_id = 1
  );
"