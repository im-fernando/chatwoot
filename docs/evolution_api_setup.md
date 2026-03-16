# Configuração Chatwoot + Evolution API (instância Fernando)

## 1. Variável no Chatwoot (.env)

Já adicionado no seu `.env`:

```env
EVOLUTION_API_BASE_URL=http://localhost:8080
```

## 2. Criar inbox no Chatwoot

1. Acesse o Chatwoot → **Configurações** → **Inboxes** → **Adicionar Inbox**.
2. Escolha o canal **WhatsApp**.
3. Selecione o provider **Evolution API**.
4. Preencha:

| Campo            | Valor |
|------------------|--------|
| **Nome da inbox** | Ex: `WhatsApp Fernando` |
| **Número de telefone** | `+558896805182` |
| **Nome da instância** | `Fernando` |
| **API key** | `a7f3c9e2b1d84f6e5a0c8b2d1e7f4a9c6b3e8d0f2a5c7e1b9d4f6a8c0e3b7d2` |
| **API base URL** | Deixe em branco (usa `EVOLUTION_API_BASE_URL` do .env = `http://localhost:8080`) |

5. Clique em **Criar WhatsApp Channel**.

## 3. Configurar webhook na Evolution API

A Evolution precisa enviar eventos para o Chatwoot. Use a **mesma API key** e a URL do Chatwoot.

**URL do webhook (Chatwoot):**

- Se o Chatwoot roda na mesma máquina: `http://localhost:3000/webhooks/evolution`
- Se o Chatwoot usa `FRONTEND_URL=http://0.0.0.0:3000` e a Evolution está em outro container/host: use o IP ou host acessível (ex.: `http://host.docker.internal:3000/webhooks/evolution` ou `http://<IP-do-host>:3000/webhooks/evolution`).

**Configurar via API da Evolution (exemplo com curl):**

```bash
curl -X POST "http://localhost:8080/webhook/set/Fernando" \
  -H "apikey: a7f3c9e2b1d84f6e5a0c8b2d1e7f4a9c6b3e8d0f2a5c7e1b9d4f6a8c0e3b7d2" \
  -H "Content-Type: application/json" \
  -d '{
    "enabled": true,
    "url": "http://localhost:3000/webhooks/evolution",
    "webhookByEvents": false,
    "webhookBase64": false,
    "events": ["MESSAGES_UPSERT", "MESSAGES_UPDATE", "MESSAGES_DELETE", "SEND_MESSAGE", "CONNECTION_UPDATE"]
  }'
```

Se Chatwoot e Evolution rodam em containers Docker na mesma máquina, use no lugar de `http://localhost:3000` a URL em que a Evolution acessa o Chatwoot (ex.: `http://host.docker.internal:3000` no Mac/Windows, ou o nome do serviço do Chatwoot no compose, ex.: `http://chatwoot:3000`).

Se a Evolution e o Chatwoot estiverem em redes diferentes (ex.: cada um em um Docker), use em `url` o endereço em que a Evolution consegue alcançar o Chatwoot (ex.: `http://host.docker.internal:3000/webhooks/evolution` no Mac/Windows, ou o IP da máquina host).

## 4. Conferir

- Status da instância na Evolution: **open** (já está).
- Envie uma mensagem para o número +558896805182 pelo WhatsApp; ela deve aparecer no Chatwoot.
- Responda pelo Chatwoot; a resposta deve chegar no WhatsApp.

## Referências

- [Evolution API – Webhooks](https://doc.evolution-api.com/v2/en/configuration/webhooks)
- [Evolution API – Set Webhook](https://doc.evolution-api.com/v2/api-reference/webhook/set)
