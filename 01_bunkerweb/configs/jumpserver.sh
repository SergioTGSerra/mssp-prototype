HOST=$JUMPSERVER_HOSTNAME
SERVER_NAMES+=("$HOST")

BUNKER_ENV+=(
    -e "${HOST}_USE_REVERSE_PROXY=yes"
    -e "${HOST}_REVERSE_PROXY_HOST=http://jms_all:80"
    -e "${HOST}_USE_PROXY_WEBSOCKET=yes"
    # -e "${HOST}_PROXY_WEBSOCKET_TIMEOUT=3600s"
    # -e "${HOST}_CUSTOM_HEADER=Upgrade \$http_upgrade"
    # -e "${HOST}_CUSTOM_HEADER_2=Connection upgrade"
    # -e "${HOST}_CUSTOM_HEADER_3=Host \$host"
    # -e "${HOST}_CUSTOM_HEADER_4=X-Real-IP \$remote_addr"
    # -e "${HOST}_CUSTOM_HEADER_5=X-Forwarded-For \$proxy_add_x_forwarded_for"
    # -e "${HOST}_CUSTOM_HEADER_6=X-Forwarded-Proto \$scheme"
    -e "${HOST}_COOKIE_FLAGS="
    -e "${HOST}_SECURITY_MODE=detect"
    -e "${HOST}_MAX_CLIENT_SIZE=100m"
    -e "${HOST}_USE_LETS_ENCRYPT=yes"
)
