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
    
    # Cache (GZIP desativado - Nextcloud já comprime, evita corrupção de SVGs)
    -e "${HOST}_USE_CLIENT_CACHE=no"
    -e "${HOST}_USE_GZIP=no"
    
    # Security headers
    -e "${HOST}_X_FRAME_OPTIONS=SAMEORIGIN"
    -e "${HOST}_ALLOWED_METHODS=GET|POST|HEAD|COPY|DELETE|LOCK|MKCOL|MOVE|PROPFIND|PROPPATCH|PUT|UNLOCK|OPTIONS|REPORT"
    -e "${HOST}_BAD_BEHAVIOR_STATUS_CODES=400 401 403 405 444"
    
    # Rate limiting (regras mais específicas primeiro)
    -e "${HOST}_LIMIT_REQ_URL_1=/apps/onlyoffice"
    -e "${HOST}_LIMIT_REQ_RATE_1=50r/s"
    -e "${HOST}_LIMIT_REQ_URL_2=/apps/text/session/sync"
    -e "${HOST}_LIMIT_REQ_RATE_2=8r/s"
    -e "${HOST}_LIMIT_REQ_URL_3=/apps"
    -e "${HOST}_LIMIT_REQ_RATE_3=5r/s"
    -e "${HOST}_LIMIT_REQ_URL_4=/core/preview"
    -e "${HOST}_LIMIT_REQ_RATE_4=5r/s"
    
    # ModSecurity CRS plugin for Nextcloud
    -e "${HOST}_MODSECURITY_CRS_PLUGINS=nextcloud-rule-exclusions"
    -e "${HOST}_USE_LETS_ENCRYPT=yes"
)
