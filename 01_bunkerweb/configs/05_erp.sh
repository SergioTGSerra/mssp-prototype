HOST=$FRAPPE_HOSTNAME
SERVER_NAMES+=("$HOST")

BUNKER_ENV+=(
    -e "${HOST}_USE_REVERSE_PROXY=yes"
    -e "${HOST}_REVERSE_PROXY_HOST=http://frappe-frontend:8080"
    -e "${HOST}_REVERSE_PROXY_WS=yes"
    -e "${HOST}_SECURITY_MODE=detect"
    -e "${HOST}_COOKIE_FLAGS="
)
