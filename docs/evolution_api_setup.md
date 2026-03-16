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

A Evolution precisa enviar eventos para o Chatwoot. **Não use `localhost`** se a Evolution roda em Docker: dentro do container, localhost é o próprio container, não o host.

### URL do webhook (escolha conforme seu cenário)

| Cenário | URL do webhook |
|--------|----------------------------------|
| **Evolution e Chatwoot em Docker (recomendado)** | **Linux:** `http://172.17.0.1:3000/webhooks/evolution` |
| | **Mac/Windows:** `http://host.docker.internal:3000/webhooks/evolution` |
| Chatwoot fora do Docker (host), Evolution em Docker | `http://host.docker.internal:3000/webhooks/evolution` (Mac/Win) ou `http://172.17.0.1:3000/webhooks/evolution` (Linux) |
| Tudo na mesma máquina, sem Docker | `http://localhost:3000/webhooks/evolution` |

### Se 172.17.0.1 não funcionar (Evolution em outro docker-compose)

Quando a Evolution está em um **docker-compose separado**, ela usa outra rede e `172.17.0.1` pode não ser acessível. Use uma destas opções:

**Opção A – IP da sua máquina (mais confiável)**  
No **host** (fora de qualquer container), rode:

```bash
hostname -I | awk '{print $1}'
```

Use o IP que aparecer (ex.: `192.168.1.10`). URL do webhook:

```text
http://<ESSE_IP>:3000/webhooks/evolution
```

**Opção B – host.docker.internal (se você edita o compose da Evolution)**  
No `docker-compose` da Evolution, no serviço da API, adicione:

```yaml
extra_hosts:
  - "host.docker.internal:host-gateway"
```

Reinicie a Evolution e use no webhook:

```text
http://host.docker.internal:3000/webhooks/evolution
```

### Configurar via API da Evolution (exemplo com curl)

Substitua `SUA_INSTANCIA`, `SUA_API_KEY` e a **url** pela URL da tabela acima (ex.: Linux com ambos em Docker → `http://172.17.0.1:3000/webhooks/evolution`).

```bash
curl -X POST "http://localhost:8080/webhook/set/SUA_INSTANCIA" \
  -H "apikey: SUA_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "enabled": true,
    "url": "http://172.17.0.1:3000/webhooks/evolution",
    "webhookByEvents": false,
    "webhookBase64": false,
    "events": ["MESSAGES_UPSERT", "MESSAGES_UPDATE", "MESSAGES_DELETE", "CONNECTION_UPDATE"]
  }'
```

## 4. Conferir

- Status da instância na Evolution: **open** (já está).
- Envie uma mensagem para o número +558896805182 pelo WhatsApp; ela deve aparecer no Chatwoot.
- Responda pelo Chatwoot; a resposta deve chegar no WhatsApp.

## 5. Se a conversa não aparecer quando alguém manda mensagem

1. **Confirme que o webhook está sendo chamado**  
   Nos logs do Rails (`docker compose logs -f rails` ou o terminal do `rails s`), ao enviar uma mensagem no WhatsApp você deve ver algo como:
   - `Evolution webhook received: instance=Fernando event=...`  
   Se não aparecer nada, a Evolution não está conseguindo chamar a URL (revise a URL do webhook e o túnel/firewall).

2. **Se o webhook chega mas a conversa não abre**  
   Veja no mesmo log:
   - `EvolutionEventsJob: processing incoming message for channel X` → o job processou a mensagem.
   - `EvolutionEventsJob: ignoring event=...` → o evento veio com outro nome (a Evolution pode enviar `messages.upsert` em vez de `MESSAGES_UPSERT`; os dois são aceitos).
   - `EvolutionEventsJob: payload has no data` → o payload está em formato inesperado.
   - `Rejected Evolution webhook: no channel for instance X` → no Chatwoot não existe inbox WhatsApp (Evolution) com **Nome da instância** = `X` (igual ao configurado na Evolution).

3. **Nome da instância**  
   O campo **Nome da instância** no inbox do Chatwoot tem que ser **exatamente** o mesmo nome da instância na Evolution (ex.: `Fernando`).

## 6. Abrir uma conversa manualmente para testar o envio

- **Se a pessoa já mandou mensagem:** a conversa aparece na **lista de conversas** do Chatwoot. Abra essa conversa e use a caixa de resposta para enviar; o envio sai pelo WhatsApp (Evolution).

- **Se a pessoa ainda não mandou mensagem:** o atalho **Nova conversa** (ícone no menu lateral) só mostra inboxes que o contato já “tem” (ex.: depois de já ter recebido mensagem no WhatsApp). Para testar o envio **sem** ter recebido nada antes:
  1. **Contatos** → **Adicionar contato** → nome e **número de telefone** (ex.: 5588999999999, sem +).
  2. Crie a conversa pela **API** (substitua `ACCOUNT_ID`, `INBOX_ID` = id do inbox WhatsApp Evolution, `CONTACT_ID` = id do contato criado, `PHONE` = número sem +, e use seu token de agente):

     ```bash
     curl -X POST "http://localhost:3000/api/v1/accounts/ACCOUNT_ID/conversations" \
       -H "Content-Type: application/json" \
       -H "api_access_token: SEU_TOKEN" \
       -d '{
         "inbox_id": INBOX_ID,
         "contact_id": CONTACT_ID,
         "source_id": "PHONE",
         "message": { "content": "Teste de envio" }
       }'
     ```
  3. No Chatwoot, abra **Conversas** e entre na conversa recém-criada; a resposta de teste já deve estar lá e você pode continuar enviando pelo painel.

## Referências

- [Evolution API – Webhooks](https://doc.evolution-api.com/v2/en/configuration/webhooks)
- [Evolution API – Set Webhook](https://doc.evolution-api.com/v2/api-reference/webhook/set)
