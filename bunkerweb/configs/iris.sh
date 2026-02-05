HOST=$IRIS_HOSTNAME
SERVER_NAMES+=("$HOST")

BUNKER_ENV+=(
    -e "${HOST}_USE_REVERSE_PROXY=yes"
    -e "${HOST}_REVERSE_PROXY_HOST=https://iriswebapp_nginx:8443"
    -e "${HOST}_SECURITY_MODE=detect"
    -e "${HOST}_USE_LETS_ENCRYPT=yes"
)
