#!/usr/bin/env bash
#
# update_zero_downtime.sh — Atualiza Chatwoot sem downtime usando blue-green deploy.
#
# Uso: sudo ./deployment/update_zero_downtime.sh
#
# Requisitos:
#   - Deploy inicial feito com deploy_vps_production.sh (blue ativo na porta 3001)
#   - Nginx configurado com upstream apontando para 127.0.0.1:3001 ou 3002
#
set -euo pipefail

APP_DIR="${APP_DIR:-/opt/chatwoot}"
BRANCH="${BRANCH:-master}"
COMPOSE_FILE_REL="${COMPOSE_FILE_REL:-deployment/docker-compose.production.custom.yaml}"
DOMAIN="${DOMAIN:-app.jssystem-server.xyz}"
NGINX_CONF="/etc/nginx/sites-available/chatwoot_${DOMAIN}.conf"
HEALTH_TIMEOUT="${HEALTH_TIMEOUT:-300}"
DRAIN_SECONDS="${DRAIN_SECONDS:-10}"

# ─── Cores para output ───────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

function log()  { echo -e "${CYAN}[$(date '+%H:%M:%S')]${NC} $*"; }
function ok()   { echo -e "${GREEN}[$(date '+%H:%M:%S')] ✔${NC} $*"; }
function warn() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] ⚠${NC} $*"; }
function die()  { echo -e "${RED}[$(date '+%H:%M:%S')] ✖ Erro:${NC} $*" >&2; exit 1; }

# ─── Validações ──────────────────────────────────────────────────────
[[ "$(id -u)" -eq 0 ]] || die "rode como root (sudo)"
[[ -d "${APP_DIR}/.git" ]] || die "repositório não encontrado em ${APP_DIR}"
[[ -f "${NGINX_CONF}" ]] || die "config do Nginx não encontrada: ${NGINX_CONF}"

cd "${APP_DIR}"

# ─── Descobrir qual slot está ativo ──────────────────────────────────
detect_active_slot() {
  if grep -q '127\.0\.0\.1:3001' "${NGINX_CONF}"; then
    echo "blue"
  elif grep -q '127\.0\.0\.1:3002' "${NGINX_CONF}"; then
    echo "green"
  else
    die "não consegui detectar o slot ativo no Nginx (esperava porta 3001 ou 3002)"
  fi
}

ACTIVE_SLOT=$(detect_active_slot)

if [[ "$ACTIVE_SLOT" == "blue" ]]; then
  NEW_SLOT="green"
  NEW_PORT="3002"
  OLD_PORT="3001"
else
  NEW_SLOT="blue"
  NEW_PORT="3001"
  OLD_PORT="3002"
fi

log "Slot ativo: ${ACTIVE_SLOT} (porta ${OLD_PORT})"
log "Novo slot:  ${NEW_SLOT} (porta ${NEW_PORT})"

# ─── 1. Atualizar código ────────────────────────────────────────────
log "Puxando atualizações do branch '${BRANCH}'..."
git fetch --all --prune
git checkout "${BRANCH}"
git pull --ff-only
ok "Código atualizado"

# ─── 2. Build da nova imagem ────────────────────────────────────────
log "Buildando nova imagem Docker (o container antigo continua rodando)..."
docker compose --project-directory "${APP_DIR}" -f "${COMPOSE_FILE_REL}" build "rails-${NEW_SLOT}"
ok "Build concluído"

# ─── 3. Rodar migrations no container novo (sem servir HTTP) ────────
log "Rodando db:chatwoot_prepare no container novo..."
docker compose --project-directory "${APP_DIR}" -f "${COMPOSE_FILE_REL}" \
  run --rm "rails-${NEW_SLOT}" \
  sh -lc "POSTGRES_STATEMENT_TIMEOUT=600s bundle exec rails db:chatwoot_prepare"
ok "Migrations concluídas"

# ─── 4. Subir o container novo ──────────────────────────────────────
log "Subindo container rails-${NEW_SLOT} na porta ${NEW_PORT}..."
docker compose --project-directory "${APP_DIR}" -f "${COMPOSE_FILE_REL}" \
  --profile "${NEW_SLOT}" \
  up -d --no-deps "rails-${NEW_SLOT}"
ok "Container rails-${NEW_SLOT} iniciado"

# ─── 5. Aguardar health check ───────────────────────────────────────
log "Aguardando health check em 127.0.0.1:${NEW_PORT} (timeout: ${HEALTH_TIMEOUT}s)..."
SECONDS=0
until curl -sf "http://127.0.0.1:${NEW_PORT}/auth/sign_in" > /dev/null 2>&1; do
  if (( SECONDS >= HEALTH_TIMEOUT )); then
    warn "Timeout no health check! Parando container novo e mantendo o antigo."
    docker compose --project-directory "${APP_DIR}" -f "${COMPOSE_FILE_REL}" \
      --profile "${NEW_SLOT}" stop "rails-${NEW_SLOT}"
    die "O container novo não ficou healthy em ${HEALTH_TIMEOUT}s. Deploy abortado, sem downtime."
  fi
  echo -n "."
  sleep 3
done
echo
ok "Container rails-${NEW_SLOT} healthy após ${SECONDS}s"

# ─── 6. Trocar upstream no Nginx ────────────────────────────────────
log "Trocando upstream do Nginx: porta ${OLD_PORT} → ${NEW_PORT}..."
sed -i "s/127\.0\.0\.1:${OLD_PORT}/127.0.0.1:${NEW_PORT}/" "${NGINX_CONF}"

nginx -t || {
  warn "Config do Nginx inválida! Revertendo..."
  sed -i "s/127\.0\.0\.1:${NEW_PORT}/127.0.0.1:${OLD_PORT}/" "${NGINX_CONF}"
  die "Nginx test falhou. Upstream revertido, container antigo continua ativo."
}

nginx -s reload
ok "Nginx recarregado — tráfego agora vai para rails-${NEW_SLOT} (porta ${NEW_PORT})"

# ─── 7. Drenar conexões do container antigo ─────────────────────────
log "Aguardando ${DRAIN_SECONDS}s para drenar conexões do container antigo..."
sleep "${DRAIN_SECONDS}"

# ─── 8. Parar o container antigo ────────────────────────────────────
log "Parando container rails-${ACTIVE_SLOT}..."
docker compose --project-directory "${APP_DIR}" -f "${COMPOSE_FILE_REL}" \
  --profile "${ACTIVE_SLOT}" stop "rails-${ACTIVE_SLOT}"
ok "Container rails-${ACTIVE_SLOT} parado"

# ─── 9. Atualizar o Sidekiq ─────────────────────────────────────────
log "Reiniciando Sidekiq..."
docker compose --project-directory "${APP_DIR}" -f "${COMPOSE_FILE_REL}" \
  up -d --no-deps sidekiq
ok "Sidekiq reiniciado"

# ─── Resumo ─────────────────────────────────────────────────────────
echo
echo -e "${GREEN}══════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Deploy zero-downtime concluído com sucesso!${NC}"
echo -e "${GREEN}══════════════════════════════════════════════════════════${NC}"
echo
echo -e "  Slot ativo: ${GREEN}${NEW_SLOT}${NC} (porta ${NEW_PORT})"
echo -e "  Slot parado: ${YELLOW}${ACTIVE_SLOT}${NC} (porta ${OLD_PORT})"
echo
echo -e "  Para ver logs: ${CYAN}cd ${APP_DIR} && docker compose -f ${COMPOSE_FILE_REL} logs -f --tail=200 rails-${NEW_SLOT}${NC}"
echo
