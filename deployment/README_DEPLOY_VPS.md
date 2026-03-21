# Deploy produção (VPS Ubuntu) — Chatwoot

Este fluxo sobe o Chatwoot em produção via Docker, com Nginx + Let's Encrypt, servindo em `https://app.jssystem-server.xyz`.

## Pré-requisitos

- VPS Ubuntu com acesso `root` (ou `sudo`)
- DNS A/AAAA apontando `app.jssystem-server.xyz` para o IP da VPS (`147.93.1.171`)
- Seu repositório no GitHub (com suas modificações)

## Deploy inicial

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

## Atualização sem downtime (blue-green)

Após o deploy inicial, use o script de atualização que faz **zero-downtime**:

```bash
cd /opt/chatwoot
sudo ./deployment/update_zero_downtime.sh
```

### Como funciona

O script usa dois containers Rails alternando entre si (blue na porta 3001, green na porta 3002):

1. Builda a nova imagem Docker (container antigo continua rodando)
2. Roda migrations no container novo
3. Sobe o container novo e aguarda health check
4. Troca o upstream do Nginx para o container novo (`nginx -s reload`, sem drop)
5. Aguarda draining de conexões e para o container antigo
6. Reinicia o Sidekiq

Se o container novo não ficar healthy, o deploy é **abortado automaticamente** sem causar downtime.

### Variáveis de ambiente opcionais

| Variável | Padrão | Descrição |
|---|---|---|
| `APP_DIR` | `/opt/chatwoot` | Diretório do projeto |
| `BRANCH` | `master` | Branch do git para atualizar |
| `DOMAIN` | `app.jssystem-server.xyz` | Domínio (para encontrar a config do Nginx) |
| `HEALTH_TIMEOUT` | `300` | Tempo máximo (segundos) para aguardar health check |
| `DRAIN_SECONDS` | `10` | Tempo de espera para drenar conexões antes de parar o antigo |

## Onde ficam os arquivos

- Código clonado: `/opt/chatwoot` (pode mudar via `APP_DIR`)
- Compose produção custom (build do repo): `deployment/docker-compose.production.custom.yaml`
- Nginx site: `/etc/nginx/sites-available/chatwoot_app.jssystem-server.xyz.conf`

## Observações importantes

- O script cria um `.env` de produção **apenas se não existir**. Se você já tem `.env` pronto, copie antes ou edite depois.
- Para e-mails (reset de senha, notificações etc.), configure SMTP no `.env`.
- O template de Nginx tem um bloco opcional para proxy do Evolution em `http://127.0.0.1:8080/` via `/evolution/`.
