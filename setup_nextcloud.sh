#!/bin/bash

podman run -d \
    --name postgres-nextcloud \
    --network=netzor-network \
    --ip ${NEXTCLOUD_DB_IP} \
    -e POSTGRES_DB=${NEXTCLOUD_DB_NAME} \
    -e POSTGRES_USER=${NEXTCLOUD_DB_USER} \
    -e POSTGRES_PASSWORD=${NEXTCLOUD_DB_PASSWORD} \
    -v nextcloud-db:/var/lib/postgresql/data:Z \
    --restart=always \
    docker.io/library/postgres:17-alpine

# Wait for Postgres
echo "Waiting for PostgreSQL to be ready..."
MAX_RETRIES=30
RETRY_COUNT=0
until podman exec postgres-nextcloud pg_isready -U ${NEXTCLOUD_DB_USER} -d ${NEXTCLOUD_DB_NAME} > /dev/null 2>&1; do
    RETRY_COUNT=$((RETRY_COUNT + 1))
    if [ $RETRY_COUNT -ge $MAX_RETRIES ]; then
        echo "ERROR: PostgreSQL failed to start after ${MAX_RETRIES} attempts."
        exit 1
    fi
    sleep 2
done

podman run -d \
    --name redis-nextcloud \
    --network=netzor-network \
    --ip ${NEXTCLOUD_REDIS_IP} \
    -v nextcloud-redis-data:/data:Z \
    --restart=always \
    docker.io/library/redis:8.4-alpine redis-server --appendonly yes

podman run -d \
    --name nextcloud-app \
    --network=netzor-network \
    --ip ${NEXTCLOUD_APP_IP} \
    -e POSTGRES_HOST=${NEXTCLOUD_DB_IP} \
    -e POSTGRES_DB=${NEXTCLOUD_DB_NAME} \
    -e POSTGRES_USER=${NEXTCLOUD_DB_USER} \
    -e POSTGRES_PASSWORD=${NEXTCLOUD_DB_PASSWORD} \
    -e REDIS_HOST=${NEXTCLOUD_REDIS_IP} \
    -e NEXTCLOUD_ADMIN_USER=${NEXTCLOUD_ADMIN_USER} \
    -e NEXTCLOUD_ADMIN_PASSWORD=${NEXTCLOUD_ADMIN_PASSWORD} \
    -e NEXTCLOUD_TRUSTED_DOMAINS="${NEXTCLOUD_HOSTNAME} ${NEXTCLOUD_WEB_IP}" \
    -e TRUSTED_PROXIES="10.90.0.0/24" \
    -e OVERWRITEHOST=${NEXTCLOUD_HOSTNAME} \
    -e OVERWRITEPROTOCOL=https \
    -v nextcloud-data:/var/www/html:Z \
    -v nextcloud-config:/var/www/html/config:Z \
    --restart=always \
    docker.io/library/nextcloud:production-fpm-alpine

podman run -d \
    --name nextcloud-web \
    --network=netzor-network \
    --ip ${NEXTCLOUD_WEB_IP} \
    -v nextcloud-data:/var/www/html:Z \
    --restart=always \
    docker.io/library/nginx:alpine

# Wait for Nginx to start
sleep 5

# Inject Nginx configuration directly into the container
# We use an unquoted heredoc (EOF) to allow shell expansion for ${NEXTCLOUD_APP_IP}.
# Nginx variables (like $uri) must be escaped with \ to prevent shell expansion.
cat << EOF | podman exec -i nextcloud-web sh -c 'cat > /etc/nginx/nginx.conf'
worker_processes auto;
error_log  /var/log/nginx/error.log warn;
pid        /var/run/nginx.pid;

events {
    worker_connections 1024;
    multi_accept on; # Melhoria: Aceita novas conexões o mais rápido possível
}

http {
    include       mime.types;
    default_type  application/octet-stream;

    # Melhoria: Suporte explícito a módulos JS modernos (caso o mime.types do sistema seja antigo)
    types {
        text/javascript mjs;
    }

    # --- Otimizações de Performance do Nginx ---
    sendfile        on;
    tcp_nopush      on;
    tcp_nodelay     on;
    keepalive_timeout  65;
    server_tokens   off; # Segurança: Oculta a versão do Nginx

    # Aumentar buffers para lidar com cabeçalhos grandes do Nextcloud
    client_body_buffer_size 512k;
    fastcgi_buffers 64 4K;

    upstream php-handler {
        server ${NEXTCLOUD_APP_IP}:9000;
    }

    server {
        listen 80;
        listen [::]:80;
        server_name _;

        root /var/www/html;
        index index.php index.html /index.php\$request_uri;

        # --- Logs ---
        # Separar logs de acesso ajuda na depuração, mas pode ser desligado para performance
        access_log /var/log/nginx/nextcloud.access.log;
        error_log /var/log/nginx/nextcloud.error.log;

        # --- Headers de Segurança e Proxy ---
        # Previne ataques de MIME sniffing
        add_header X-Content-Type-Options nosniff;
        add_header X-XSS-Protection "1; mode=block";
        add_header X-Robots-Tag "noindex, nofollow" always;
        add_header X-Download-Options noopen;
        add_header X-Permitted-Cross-Domain-Policies none;
        add_header Referrer-Policy no-referrer;

        # IMPORTANTE: HSTS (Strict-Transport-Security)
        # Se este Nginx estiver atrás de um proxy SSL, o proxy geralmente lida com isso.
        # Se o Nextcloud reclamar, descomente a linha abaixo:
        # add_header Strict-Transport-Security "max-age=15768000; includeSubDomains; preload;" always;

        # Configurações de upload (deve bater com o php.ini)
        client_max_body_size 10G;

        # --- Compressão Gzip ---
        gzip on;
        gzip_vary on;
        gzip_comp_level 4;
        gzip_min_length 256;
        gzip_proxied expired no-cache no-store private no_last_modified no_etag auth;
        gzip_types application/atom+xml application/javascript application/json application/ld+json application/manifest+json application/rss+xml application/vnd.geo+json application/vnd.ms-fontobject application/x-font-ttf application/x-web-app-manifest+json application/xhtml+xml application/xml font/opentype image/bmp image/svg+xml image/x-icon text/cache-manifest text/css text/plain text/vcard text/vnd.rim.location.xloc text/vtt text/x-component text/x-cross-domain-policy;

        # --- Redirecionamento WebDAV ---
        location = / {
            if ( \$http_user_agent ~ ^DavClnt ) {
                return 302 /remote.php/webdav/\$is_args\$args;
            }
        }

        location / {
            try_files \$uri \$uri/ /index.php\$request_uri;
        }

        location = /robots.txt {
            allow all;
            log_not_found off;
            access_log off;
        }

        # --- Regras .well-known (Modernas) ---
        # O Nextcloud moderno resolve quase tudo via index.php
        location ^~ /.well-known {
            location = /.well-known/carddav { return 301 /remote.php/dav/; }
            location = /.well-known/caldav  { return 301 /remote.php/dav/; }
            
            # Suporte para certificados Let's Encrypt (caso necessário neste nível)
            location /.well-known/acme-challenge    { try_files \$uri \$uri/ =404; }
            location /.well-known/pki-validation    { try_files \$uri \$uri/ =404; }

            return 301 /index.php\$request_uri;
        }

        # --- Proteção de diretórios sensíveis ---
        location ~ ^/(?:build|tests|config|lib|3rdparty|templates|data)/ {
            deny all;
        }
        location ~ ^/(?:\.|autotest|occ|issue|indie|db_|console) {
            deny all;
        }

        # --- Tratamento PHP (Core do Nextcloud) ---
        location ~ ^/(?:index|remote|public|cron|core/ajax/update|status|ocs/v[12]|updater/.+|ocs-provider/.+)\.php(?:$|/) {
            fastcgi_split_path_info ^(.+?\.php)(/.*)$;
            set \$path_info \$fastcgi_path_info;
            try_files \$fastcgi_script_name =404;
            
            include fastcgi_params;
            
            fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
            fastcgi_param PATH_INFO \$path_info;
            
            # HTTPS on: Essencial se você tem um Proxy reverso SSL na frente deste servidor.
            # Sem isso, o Nextcloud gera links http:// inseguros.
            fastcgi_param HTTPS on;
            
            fastcgi_param modHeadersAvailable true;
            fastcgi_param front_controller_active true;
            fastcgi_pass php-handler;
            
            fastcgi_intercept_errors on;
            fastcgi_request_buffering off;
            
            # CORREÇÃO CRÍTICA: Timeouts
            # Uploads grandes ou operações pesadas (indexação) falharão com o padrão de 60s
            fastcgi_read_timeout 3600;
            fastcgi_send_timeout 3600;
        }

        location ~ ^/(?:updater|ocs-provider)(?:$|/) {
            try_files \$uri/ =404;
            index index.php;
        }

        # --- Cache de Assets Estáticos ---
        location ~ \.(?:css|js|mjs|woff2?|svg|gif|map)$ {
            try_files \$uri /index.php\$request_uri;
            # Cache longo para performance
            add_header Cache-Control "public, max-age=15778463";
            
            # Repetição necessária dos headers de segurança dentro do location block
            add_header X-Content-Type-Options nosniff;
            add_header X-XSS-Protection "1; mode=block";
            add_header X-Robots-Tag "noindex, nofollow" always;
            add_header X-Download-Options noopen;
            add_header X-Permitted-Cross-Domain-Policies none;
            add_header Referrer-Policy no-referrer;
            
            access_log off;
        }

        location ~ \.(?:png|html|ttf|ico|jpg|jpeg|bcmap|mp4|webm)$ {
            try_files \$uri /index.php\$request_uri;
            access_log off;
        }
    }
}
EOF

# Reload Nginx to apply the new configuration
podman exec nextcloud-web nginx -s reload




# 5. Configure Maintenance Window (4 AM to 8 AM)
#podman exec -u www-data nextcloud-app php occ config:system:set maintenance_window_start --value=4 --type=integer

# 6. Perform Mimetype Migrations
#podman exec -u www-data nextcloud-app php occ maintenance:repair --include-expensive

# 7. Add Missing Database Indices
#podman exec -u www-data nextcloud-app php occ db:add-missing-indices