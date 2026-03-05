HOST=$FREEIPA_HOSTNAME
SERVER_NAMES+=("$HOST")

BUNKER_ENV+=(
    -e "${HOST}_USE_REVERSE_PROXY=yes"
    -e "${HOST}_REVERSE_PROXY_HOST=https://freeipa"
    -e "${HOST}_REVERSE_PROXY_WS=yes"
    -e "${HOST}_SECURITY_MODE=detect"
    # Restringir acesso — apenas rede interna (JumpServer/PAM)
    -e "${HOST}_USE_GREYLIST=yes"
    -e "${HOST}_GREYLIST_IP=${WAF_SUBNET}"
    -e "${HOST}_USE_BLACKLIST=yes"
    -e "${HOST}_BLACKLIST_IP=0.0.0.0/0"
)
