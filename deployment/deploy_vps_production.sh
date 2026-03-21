#!/usr/bin/env bash
set -euo pipefail

DOMAIN="${DOMAIN:-app.jssystem-server.xyz}"
LE_EMAIL="${LE_EMAIL:-admin@${DOMAIN}}"
REPO_URL="${REPO_URL:-}"
BRANCH="${BRANCH:-master}"
APP_DIR="${APP_DIR:-/opt/chatwoot}"

COMPOSE_FILE_REL="${COMPOSE_FILE_REL:-deployment/docker-compose.production.custom.yaml}"
SECRETS_OUT="${SECRETS_OUT:-/root/chatwoot_production_secrets_${DOMAIN}.txt}"

function die() {
  echo "Erro: $*" >&2
  exit 1
}

if [[ "$(id -u)" -ne 0 ]]; then
  die "rode como root (ex: sudo DOMAIN=${DOMAIN} REPO_URL=<git> $0)"
fi

export DEBIAN_FRONTEND=noninteractive

echo "[1/8] Instalando dependências do sistema (Docker, Nginx, Certbot, Git)..."
apt-get update -y
apt-get install -y --no-install-recommends \
  ca-certificates curl gnupg git openssl \
  nginx ufw \
  certbot python3-certbot-nginx \
  docker.io

# BuildKit/Buildx (necessário para builds do Compose v2 em algumas distros)
if apt-cache show docker-buildx >/dev/null 2>&1; then
  apt-get install -y --no-install-recommends docker-buildx
fi

# Ubuntu 24.04 (noble) fornece Compose v2 como docker-compose-v2.
# Alguns mirrors também expõem um pacote virtual "docker-compose".
if apt-cache show docker-compose-v2 >/dev/null 2>&1; then
  apt-get install -y --no-install-recommends docker-compose-v2
elif apt-cache show docker-compose >/dev/null 2>&1; then
  apt-get install -y --no-install-recommends docker-compose
else
  die "não achei docker-compose-v2/docker-compose via apt. Habilite universe ou instale Docker/Compose pelo repositório oficial do Docker."
fi

systemctl enable --now docker
systemctl enable --now nginx

echo "[2/8] Firewall (UFW) para SSH + HTTP/HTTPS..."
ufw allow OpenSSH >/dev/null || true
ufw allow 'Nginx Full' >/dev/null || true
ufw --force enable >/dev/null || true

echo "[3/8] Clonando/atualizando repositório em ${APP_DIR}..."
if [[ -d "${APP_DIR}/.git" ]]; then
  if [[ -n "${REPO_URL}" ]]; then
    git -C "${APP_DIR}" remote set-url origin "${REPO_URL}" || true
  fi
  git -C "${APP_DIR}" fetch --all --prune
  git -C "${APP_DIR}" checkout "${BRANCH}"
  git -C "${APP_DIR}" pull --ff-only
else
  if [[ -z "${REPO_URL}" ]]; then
    die "repo não encontrado em ${APP_DIR}. Passe REPO_URL para clonar (ex: REPO_URL=https://github.com/usuario/chatwoot.git)"
  fi
  rm -rf "${APP_DIR}"
  git clone --branch "${BRANCH}" --depth 1 "${REPO_URL}" "${APP_DIR}"
fi

cd "${APP_DIR}"

if [[ ! -f "${COMPOSE_FILE_REL}" ]]; then
  die "não encontrei ${COMPOSE_FILE_REL} no repo. Confirme que você puxou os commits com os arquivos de deploy."
fi

echo "[4/8] Criando .env de produção (se não existir)..."
GENERATED_ENV="false"
if [[ ! -f ".env" ]]; then
  SECRET_KEY_BASE="$(openssl rand -hex 64)"
  POSTGRES_PASSWORD="$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 32)"
  REDIS_PASSWORD="$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 32)"
  GENERATED_ENV="true"

  cat > .env <<EOF
SECRET_KEY_BASE=${SECRET_KEY_BASE}
FRONTEND_URL=https://${DOMAIN}
FORCE_SSL=true
ENABLE_ACCOUNT_SIGNUP=false

RAILS_ENV=production
NODE_ENV=production
INSTALLATION_ENV=docker

POSTGRES_HOST=postgres
POSTGRES_USERNAME=postgres
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}

REDIS_URL=redis://redis:6379
REDIS_PASSWORD=${REDIS_PASSWORD}

# Ajuste SMTP se você for enviar e-mails (recomendado em produção)
# MAILER_SENDER_EMAIL=Chatwoot <accounts@${DOMAIN}>
# SMTP_DOMAIN=${DOMAIN}
# SMTP_ADDRESS=
# SMTP_PORT=587
# SMTP_USERNAME=
# SMTP_PASSWORD=
# SMTP_AUTHENTICATION=login
# SMTP_ENABLE_STARTTLS_AUTO=true
# SMTP_OPENSSL_VERIFY_MODE=peer

# Evolution API (WhatsApp provider)
# EVOLUTION_API_BASE_URL=http://localhost:8080
EOF
  chmod 600 .env

  cat > "${SECRETS_OUT}" <<EOF
Domain: ${DOMAIN}
Generated at: $(date -Is)

SECRET_KEY_BASE=${SECRET_KEY_BASE}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
REDIS_PASSWORD=${REDIS_PASSWORD}

Env file: ${APP_DIR}/.env
EOF
  chmod 600 "${SECRETS_OUT}"
fi

echo "[5/8] Buildando e subindo Postgres/Redis..."
docker compose --project-directory "${APP_DIR}" -f "${COMPOSE_FILE_REL}" up -d --remove-orphans postgres redis

echo "[6/8] Preparando o banco (db:chatwoot_prepare)..."
docker compose --project-directory "${APP_DIR}" -f "${COMPOSE_FILE_REL}" --profile blue run --rm rails-blue sh -lc "POSTGRES_STATEMENT_TIMEOUT=600s bundle exec rails db:chatwoot_prepare"

echo "[7/8] Subindo Chatwoot (rails-blue + sidekiq)..."
docker compose --project-directory "${APP_DIR}" -f "${COMPOSE_FILE_REL}" --profile blue up -d --remove-orphans --build rails-blue sidekiq

echo "[8/8] Configurando Nginx para ${DOMAIN} e emitindo SSL..."
install -d /etc/ssl
if [[ ! -f /etc/ssl/dhparam ]]; then
  openssl dhparam -out /etc/ssl/dhparam 2048
fi

HTTP_ONLY="/etc/nginx/sites-available/chatwoot_${DOMAIN}_http.conf"
cat > "${HTTP_ONLY}" <<EOF
server {
  listen 80;
  listen [::]:80;
  server_name ${DOMAIN} www.${DOMAIN};

  access_log /var/log/nginx/chatwoot_access_80.log;
  error_log /var/log/nginx/chatwoot_error_80.log;

  location /.well-known/acme-challenge/ {
    root /var/www/html;
  }

  location / {
    proxy_pass http://127.0.0.1:3001;
    proxy_redirect off;

    proxy_pass_header Authorization;
    proxy_set_header Host \$host;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;

    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";

    client_max_body_size 0;
    proxy_read_timeout 36000s;
  }
}
EOF

ln -sf "${HTTP_ONLY}" "/etc/nginx/sites-enabled/chatwoot_${DOMAIN}.conf"
rm -f /etc/nginx/sites-enabled/default || true

nginx -t
systemctl reload nginx

# Certbot (não-interativo). Requer DNS apontando o domínio para a VPS.
certbot certonly --webroot \
  -w /var/www/html \
  -d "${DOMAIN}" \
  --agree-tos \
  -m "${LE_EMAIL}" \
  --non-interactive \
  --no-eff-email

TLS_CONF="/etc/nginx/sites-available/chatwoot_${DOMAIN}.conf"
sed "s/__DOMAIN__/${DOMAIN}/g" deployment/nginx_chatwoot_app.conf.template > "${TLS_CONF}"
ln -sf "${TLS_CONF}" "/etc/nginx/sites-enabled/chatwoot_${DOMAIN}.conf"

nginx -t
systemctl reload nginx

echo
echo "Deploy finalizado."
echo "- URL: https://${DOMAIN}"
echo "- Containers: $(docker compose --project-directory "${APP_DIR}" -f "${COMPOSE_FILE_REL}" ps --status running | wc -l) rodando"
if [[ "${GENERATED_ENV}" == "true" ]]; then
  echo "- Credenciais geradas e salvas em: ${SECRETS_OUT} (permissão 600)"
  echo "  IMPORTANTE: salve essas senhas e depois guarde/apague esse arquivo."
fi
echo
echo "Dica: para ver logs:"
echo "  cd ${APP_DIR} && docker compose -f ${COMPOSE_FILE_REL} logs -f --tail=200 rails"

