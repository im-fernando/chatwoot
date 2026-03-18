# Menu de triagem WhatsApp (1 / 2 / 3)

Fluxo fixo para caixas de entrada **WhatsApp** (Cloud, 360dialog, Evolution) **por inbox**.

## Ativar

1. **Configurações** (ícone de engrenagem) → **Caixas de entrada** → escolha a inbox **WhatsApp**.
2. Na aba de configurações da inbox, ative **“WhatsApp menu triage (1 / 2 / 3)”** e salve.

Cada número/WhatsApp pode ter o menu **ligado ou desligado** de forma independente.

## Ajustar times

Em `app/services/whatsapp/menu_triage_service.rb`, constantes **`TEAM_PDV_ID`**, **`TEAM_GERENCIAL_ID`**, **`TEAM_FINANCEIRO_ID`** — use os IDs dos times da conta (mesmos da URL ao editar um time).

## Comportamento

- Novas conversas dessa inbox começam em **pending** até o cliente escolher o setor.
- Menu **1 — PDV**, **2 — Gerencial**, **3 — Financeiro**.
- Entre **17h e 6h59** (**America/Sao_Paulo**), a opção 3 some do menu; se digitar 3, aviso de fora do horário.
- Opção inválida → pede 1, 2 ou 3 (ou 1 ou 2 fora do horário do financeiro).
- Escolha válida → conversa **aberta**, time atribuído, mensagem com **protocolo** (`display_id`).

## Migração

Após atualizar o código: `rails db:migrate` (coluna `whatsapp_menu_triage_enabled` em `inboxes`).
