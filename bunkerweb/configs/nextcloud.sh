HOST=$NEXTCLOUD_HOSTNAME
SERVER_NAMES+=("$HOST")

BUNKER_ENV+=(
    -e "${HOST}_USE_REVERSE_PROXY=yes"
    -e "${HOST}_REVERSE_PROXY_HOST=http://nextcloud-aio-apache:11000"
    -e "${HOST}_SECURITY_MODE=detect"
    # Desativar modificação de cookies para aplicações que gerem os seus próprios cookies
    -e "${HOST}_COOKIE_FLAGS="
    
    # Configurações específicas para Nextcloud
    -e "${HOST}_REVERSE_PROXY_WS=yes"
    -e "${HOST}_REVERSE_PROXY_INTERCEPT_ERRORS=no"
    -e "${HOST}_REVERSE_PROXY_CONNECT_TIMEOUT=300s"
    -e "${HOST}_REVERSE_PROXY_READ_TIMEOUT=300s"
    -e "${HOST}_REVERSE_PROXY_SEND_TIMEOUT=300s"
    -e "${HOST}_MAX_CLIENT_SIZE=16G"
    -e "${HOST}_CLIENT_BODY_TIMEOUT=300s"
    -e "${HOST}_PROXY_BUFFERING=no"
)
