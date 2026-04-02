#!/bin/bash
source "$(dirname "$0")/../utils.sh"; script_init;

# Start IRIS with Podman Compose
podman compose -p "$(basename "$(cd "$(dirname "$0")" && pwd)" | sed 's/^[0-9]*_//')" -f "$(dirname "$0")/compose.yaml" up -d

# Grant admin permissions to MAIN_USER
# Pre-creates the user in the DB so that on first OAuth login,
# the user already has Administrator group membership.

echo ">> Waiting for IRIS to initialize the database..."
wait_for_container_healthy "iriswebapp_db"

echo ">> Waiting for database tables and default data to be initialized by IRIS..."
until podman exec iriswebapp_db psql -U postgres -d iris_db -t -c "SELECT 1 FROM organisations WHERE org_id = 1;" 2>/dev/null | grep -q 1; do
  sleep 2
done
until podman exec iriswebapp_db psql -U postgres -d iris_db -t -c "SELECT 1 FROM groups WHERE group_name = 'Administrators';" 2>/dev/null | grep -q 1; do
  sleep 2
done

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