#!/bin/bash
set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Diretórios
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
CERT_OUTPUT_DIR="$SCRIPT_DIR/certs"
LETSENCRYPT_DIR="$SCRIPT_DIR/letsencrypt"

# Criar diretórios se não existirem
mkdir -p "$CERT_OUTPUT_DIR"
mkdir -p "$LETSENCRYPT_DIR"

echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║      Certbot (Podman) - DNS Challenge Certificate Generator    ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Verificar se o domínio foi fornecido
if [ -z "$1" ]; then
    echo -e "${YELLOW}Uso: $0 <domínio> [domínios adicionais...]${NC}"
    echo -e "${YELLOW}Exemplo: $0 netzor.pt *.netzor.pt${NC}"
    echo ""
    echo -e "Domínios disponíveis no .env:"
    
    # Listar domínios do .env
    if [ -f "$PWD/.env" ]; then
        grep -E "_HOSTNAME=" "$PWD/.env" | while read -r line; do
            domain=$(echo "$line" | cut -d'=' -f2)
            echo -e "  - ${GREEN}$domain${NC}"
        done
    fi
    exit 1
fi

# Construir lista de domínios para certbot
DOMAINS=""
for domain in "$@"; do
    DOMAINS="$DOMAINS -d $domain"
done

echo -e "${BLUE}>> Domínios a certificar:${NC}"
for domain in "$@"; do
    echo -e "   - ${GREEN}$domain${NC}"
done
echo ""

echo -e "${BLUE}>> A iniciar o desafio DNS...${NC}"
echo ""
echo -e "${YELLOW}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${YELLOW}║                    ATENÇÃO - AÇÃO NECESSÁRIA                   ║${NC}"
echo -e "${YELLOW}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "O Certbot vai apresentar um ou mais registos TXT que deve adicionar"
echo -e "ao seu DNS. Siga estas instruções:"
echo ""
echo -e "${CYAN}1.${NC} Quando aparecer o registo TXT, copie-o"
echo -e "${CYAN}2.${NC} Aceda ao painel de gestão do seu domínio"
echo -e "${CYAN}3.${NC} Adicione um registo TXT com:"
echo -e "   - Nome/Host: ${GREEN}_acme-challenge${NC} (ou o subdomínio indicado)"
echo -e "   - Valor: ${GREEN}<o valor que o Certbot mostrar>${NC}"
echo -e "${CYAN}4.${NC} Aguarde 1-5 minutos para propagação DNS"
echo -e "${CYAN}5.${NC} Prima ENTER no Certbot para continuar"
echo ""
echo -e "${RED}IMPORTANTE:${NC} Se tiver múltiplos domínios (ex: wildcard), terá de"
echo -e "adicionar múltiplos registos TXT."
echo ""
echo -e "─────────────────────────────────────────────────────────────────"
read -p "Prima ENTER para continuar com o desafio DNS..."
echo ""

# Executar certbot em container Podman com desafio DNS manual
podman run -it --rm \
    --name certbot \
    -v "$LETSENCRYPT_DIR:/etc/letsencrypt:Z" \
    -v "$CERT_OUTPUT_DIR:/certs:Z" \
    docker.io/certbot/certbot:latest \
    certonly \
    --manual \
    --preferred-challenges dns \
    --agree-tos \
    --no-eff-email \
    --register-unsafely-without-email \
    $DOMAINS

# Verificar se o certificado foi gerado
FIRST_DOMAIN=$(echo "$1" | sed 's/\*\.//')
CERT_PATH="$LETSENCRYPT_DIR/live/$FIRST_DOMAIN"

if [ -d "$CERT_PATH" ]; then
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║            ✓ Certificado gerado com sucesso!                   ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BLUE}Localização dos certificados:${NC}"
    echo -e "  Certificado: ${CYAN}$CERT_PATH/fullchain.pem${NC}"
    echo -e "  Chave privada: ${CYAN}$CERT_PATH/privkey.pem${NC}"
    echo ""
    
    # Copiar certificados para o diretório de output
    echo -e "${BLUE}>> A copiar certificados para $CERT_OUTPUT_DIR...${NC}"
    cp -L "$CERT_PATH/fullchain.pem" "$CERT_OUTPUT_DIR/"
    cp -L "$CERT_PATH/privkey.pem" "$CERT_OUTPUT_DIR/"
    
    echo -e "${GREEN}>> Certificados copiados para:${NC}"
    echo -e "   $CERT_OUTPUT_DIR/fullchain.pem"
    echo -e "   $CERT_OUTPUT_DIR/privkey.pem"
    echo ""
    
    # Mostrar informações do certificado
    echo -e "${BLUE}Informações do certificado:${NC}"
    openssl x509 -in "$CERT_OUTPUT_DIR/fullchain.pem" -noout -dates -subject | head -5
    echo ""
    
    echo -e "${YELLOW}Próximos passos:${NC}"
    echo -e "1. Configure o BunkerWeb para usar os certificados:"
    echo -e "   ${CYAN}-e \"\${HOST}_USE_CUSTOM_SSL=yes\"${NC}"
    echo -e "   ${CYAN}-e \"\${HOST}_CUSTOM_SSL_CERT=/path/to/fullchain.pem\"${NC}"
    echo -e "   ${CYAN}-e \"\${HOST}_CUSTOM_SSL_KEY=/path/to/privkey.pem\"${NC}"
    echo ""
    echo -e "2. Ou use o script de renovação automática"
    echo ""
else
    echo -e "${RED}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║            ✗ Erro ao gerar o certificado                       ║${NC}"
    echo -e "${RED}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "Verifique se os registos DNS foram adicionados corretamente."
    echo -e "Pode verificar a propagação em: ${CYAN}https://dnschecker.org${NC}"
    exit 1
fi
