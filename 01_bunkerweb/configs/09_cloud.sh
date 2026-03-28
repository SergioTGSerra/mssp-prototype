# Nextcloud Hub Configuration
HOST=$NEXTCLOUD_HOSTNAME
SERVER_NAMES+=("$HOST")

BUNKER_ENV+=(
    -e "${HOST}_USE_REVERSE_PROXY=yes"
    -e "${HOST}_REVERSE_PROXY_HOST=http://nextcloud-aio-apache:11000"
    -e "${HOST}_SECURITY_MODE=detect"
    
    # Disable cookie flag modification to allow the application to manage its own cookies
    -e "${HOST}_COOKIE_FLAGS="
    
    # Nextcloud-specific reverse proxy optimizations
    -e "${HOST}_REVERSE_PROXY_WS=yes"
    -e "${HOST}_REVERSE_PROXY_INTERCEPT_ERRORS=no"
    -e "${HOST}_REVERSE_PROXY_CONNECT_TIMEOUT=300s"
    -e "${HOST}_REVERSE_PROXY_READ_TIMEOUT=300s"
    -e "${HOST}_REVERSE_PROXY_SEND_TIMEOUT=300s"
    -e "${HOST}_MAX_CLIENT_SIZE=16G"
    -e "${HOST}_CLIENT_BODY_TIMEOUT=300s"
    -e "${HOST}_PROXY_BUFFERING=no"
    
    # Caching and Compression
    # GZIP is disabled because Nextcloud already handles compression, avoiding SVG corruption
    -e "${HOST}_USE_CLIENT_CACHE=no"
    -e "${HOST}_USE_GZIP=no"
    
    # Security Headers and Allowed Methods
    -e "${HOST}_X_FRAME_OPTIONS=SAMEORIGIN"
    -e "${HOST}_ALLOWED_METHODS=GET|POST|HEAD|COPY|DELETE|LOCK|MKCOL|MOVE|PROPFIND|PROPPATCH|PUT|UNLOCK|OPTIONS|REPORT"
    -e "${HOST}_BAD_BEHAVIOR_STATUS_CODES=400 401 403 405 444"
    
    # Rate Limiting (Specific rules first)
    # OnlyOffice integration
    -e "${HOST}_LIMIT_REQ_URL_1=/apps/onlyoffice"
    -e "${HOST}_LIMIT_REQ_RATE_1=50r/s"
    # Text app sync sessions
    -e "${HOST}_LIMIT_REQ_URL_2=/apps/text/session/sync"
    -e "${HOST}_LIMIT_REQ_RATE_2=8r/s"
    # General apps access
    -e "${HOST}_LIMIT_REQ_URL_3=/apps"
    -e "${HOST}_LIMIT_REQ_RATE_3=5r/s"
    # Core previews
    -e "${HOST}_LIMIT_REQ_URL_4=/core/preview"
    -e "${HOST}_LIMIT_REQ_RATE_4=5r/s"
    
    # ModSecurity CRS plugin for Nextcloud exclusions
    -e "${HOST}_MODSECURITY_CRS_PLUGINS=nextcloud-rule-exclusions"
)
