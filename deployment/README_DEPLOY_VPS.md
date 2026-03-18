# Deploy produção (VPS Ubuntu) — Chatwoot

Este fluxo sobe o Chatwoot em produção via Docker, com Nginx + Let’s Encrypt, servindo em `https://app.jssystem-server.xyz`.

## Pré-requisitos

- VPS Ubuntu com acesso `root` (ou `sudo`)
- DNS A/AAAA apontando `app.jssystem-server.xyz` para o IP da VPS (`147.93.1.171`)
- Seu repositório no GitHub (com suas modificações)

## Como rodar

Na VPS:

```bash
curl -fsSL https://raw.githubusercontent.com/<SEU_USUARIO>/<SEU_REPO>/<BRANCH>/deployment/deploy_vps_production.sh -o deploy.sh
chmod +x deploy.sh

sudo DOMAIN=app.jssystem-server.xyz \
  LE_EMAIL=admin@app.jssystem-server.xyz \
  REPO_URL=https://github.com/<SEU_USUARIO>/<SEU_REPO>.git \
  BRANCH=master \
  ./deploy.sh
```

## Onde ficam os arquivos

- Código clonado: `/opt/chatwoot` (pode mudar via `APP_DIR`)
- Compose produção custom (build do repo): `deployment/docker-compose.production.custom.yaml`
- Nginx site: `/etc/nginx/sites-available/chatwoot_app.jssystem-server.xyz.conf`

## Observações importantes

- O script cria um `.env` de produção **apenas se não existir**. Se você já tem `.env` pronto, copie antes ou edite depois.
- Para e-mails (reset de senha, notificações etc.), configure SMTP no `.env`.
- O template de Nginx tem um bloco opcional para proxy do Evolution em `http://127.0.0.1:8080/` via `/evolution/`.

