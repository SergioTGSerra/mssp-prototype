#!/bin/bash
source utils.sh; script_init;

# Create jumpserver-bind system user in FreeIPA
freeipa_create_system_account "jumpserver-bind" "JumpServer" "Bind" "${JUMPSERVER_LDAP_BIND_PASSWORD}" "JumpServer Bind System Account"

# Criar networks se não existirem
podman network exists jumpserver_default || podman network create jumpserver_default

# Create volumes if they don't exist
podman volume exists jsdata || podman volume create jsdata
podman volume exists pgdata || podman volume create pgdata

if podman container exists jumpserver; then
  podman start jumpserver
else
  podman run --name jumpserver -d \
     --network=jumpserver_default \
     -e SECRET_KEY=PleaseChangeMe \
     -e BOOTSTRAP_TOKEN=PleaseChangeMe \
     -e AUTH_LDAP=true \
     -e AUTH_LDAP_SERVER_URI="ldap://${FREEIPA_HOSTNAME}" \
     -e AUTH_LDAP_BIND_DN="${JUMPSERVER_LDAP_BIND_DN}" \
     -e AUTH_LDAP_BIND_PASSWORD="${JUMPSERVER_LDAP_BIND_PASSWORD}" \
     -e AUTH_LDAP_SEARCH_OU="${FREEIPA_USER_DN}" \
     -e AUTH_LDAP_SEARCH_FILTER="(uid=%(user)s)" \
     -e AUTH_LDAP_USER_ATTR_MAP='{"username": "uid", "name": "cn", "email": "mail"}' \
     -v jsdata:/opt/data \
     -v pgdata:/var/lib/postgresql \
     --tmpfs /opt/download:rw \
     --tmpfs /var/log/nginx:rw \
     -p 2222:2222 \
     docker.io/jumpserver/jms_all:v4.10.16

  podman network connect waf_default jumpserver
fi

# Set JumpServer default admin password (retrying to allow DB initialization)
echo "Setting JumpServer default admin password..."
MAX_RETRIES=15
RETRY_COUNT=0
SUCCESS=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    # Run python script inside the container to change the admin password non-interactively
    if podman exec -i \
        -e REDIS_PASSWORD=PleaseChangeMe \
        -e DB_ENGINE=postgresql \
        -e DB_HOST=127.0.0.1 \
        -e DB_PORT=5432 \
        -e DB_USER=postgres \
        -e DB_PASSWORD=PleaseChangeMe \
        -e DB_NAME=jumpserver \
        -e JMP_PASS="${JUMPSERVER_ADMIN_PASSWORD}" \
        jumpserver /opt/py3/bin/python >/dev/null 2>&1 <<'EOF'
import sys
sys.path.append('/opt/jumpserver/apps')
import os, django
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'jumpserver.settings')
django.setup()
from users.models import User
u = User.objects.get(username='admin')
u.set_password(os.environ.get('JMP_PASS'))
u.save()
EOF
    then
        echo "JumpServer admin password configured successfully."
        SUCCESS=1
        break
    else
        RETRY_COUNT=$((RETRY_COUNT + 1))
        sleep 10
    fi
done

if [ $SUCCESS -eq 0 ]; then
    echo "Warning: Failed to set JumpServer admin password automatically. The system might take longer to initialize."
fi
