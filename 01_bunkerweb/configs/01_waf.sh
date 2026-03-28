# BunkerWeb UI and WAF Management Configuration
HOST=$BUNKERWEB_HOSTNAME
SERVER_NAMES+=("$HOST")

BUNKER_ENV+=(
    -e "${HOST}_USE_UI=yes"
    -e "${HOST}_USE_REVERSE_PROXY=yes"
    -e "${HOST}_REVERSE_PROXY_HOST=http://127.0.0.1:7000"
    -e "${HOST}_REVERSE_PROXY_INTERCEPT_ERRORS=no"
    -e "${HOST}_REVERSE_PROXY_WS=yes"
    -e "${HOST}_SECURITY_MODE=detect"
    
    # Access Control - Restrict to internal network only
    -e "${HOST}_USE_GREYLIST=yes"
    -e "${HOST}_GREYLIST_IP=${WAF_SUBNET}"
    -e "${HOST}_USE_BLACKLIST=yes"
    -e "${HOST}_BLACKLIST_IP=0.0.0.0/0"
)
