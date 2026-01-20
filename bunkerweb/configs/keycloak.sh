HOST=$KEYCLOAK_HOSTNAME
SERVER_NAMES+=("$HOST")

BUNKER_ENV+=(
    -e "${HOST}_USE_REVERSE_PROXY=yes"
    -e "${HOST}_REVERSE_PROXY_HOST=http://keycloak"
    -e "${HOST}_SECURITY_MODE=detect"
    # Desativar modificação de cookies para aplicações que gerem os seus próprios cookies
    -e "${HOST}_COOKIE_FLAGS="
    -e "${HOST}_USE_LETS_ENCRYPT=yes"
)
