HOST=$BUNKERWEB_HOSTNAME
SERVER_NAMES+=("$HOST")

BUNKER_ENV+=(
    -e "${HOST}_USE_UI=yes"
    -e "${HOST}_USE_REVERSE_PROXY=yes"
    -e "${HOST}_REVERSE_PROXY_HOST=http://127.0.0.1:7000"
    -e "${HOST}_REVERSE_PROXY_INTERCEPT_ERRORS=no"
    -e "${HOST}_SECURITY_MODE=detect"
    # Allow access to the UI from anywhere (can be restricted later if needed)
    -e "${HOST}_USE_WHITELIST=no"
)
