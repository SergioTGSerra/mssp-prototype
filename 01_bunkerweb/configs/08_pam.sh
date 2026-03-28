# JumpServer PAM Configuration
HOST=$JUMPSERVER_HOSTNAME
SERVER_NAMES+=("$HOST")

BUNKER_ENV+=(
    -e "${HOST}_USE_REVERSE_PROXY=yes"
    -e "${HOST}_REVERSE_PROXY_HOST=http://jumpserver"
    -e "${HOST}_REVERSE_PROXY_WS=yes"
    -e "${HOST}_SECURITY_MODE=detect"
    
    # Disable cookie flag modification to allow the application to manage its own cookies
    -e "${HOST}_COOKIE_FLAGS="
)
