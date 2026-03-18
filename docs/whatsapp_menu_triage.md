# Menu de triagem WhatsApp (1 / 2 / 3)

Fluxo fixo para caixas de entrada **WhatsApp** (Cloud, 360dialog, Evolution) **por inbox**.

## Ativar

1. **Configurações** (ícone de engrenagem) → **Caixas de entrada** → escolha a inbox **WhatsApp**.
2. Na aba de configurações da inbox, ative **“WhatsApp menu triage (1 / 2 / 3)”** e salve.

Cada número/WhatsApp pode ter o menu **ligado ou desligado** de forma independente.

## Ajustar times

Em `app/services/whatsapp/menu_triage_service.rb`: **`TEAM_PDV_ID`**, **`TEAM_GERENCIAL_ID`**, **`TEAM_FISCAL_ID`**, **`TEAM_FINANCEIRO_ID`**.

## Comportamento

- Novas conversas dessa inbox começam em **pending** até o cliente escolher o setor.
- **1** — PDV/PAY (Sistema dos frentistas) · **2** — Gerencial (Sistema de gerência do posto) · **3** — Fiscal · **4** — Financeiro.
- Entre **17h e 6h59** (**America/Sao_Paulo**), **Fiscal** e **Financeiro** ficam indisponíveis (no WhatsApp: `*Fiscal*` e `*Financeiro*` em negrito no menu); só **1** e **2** aceitos.
- Protocolo no formato **`#` + número com zeros à esquerda até 4 dígitos** (ex.: `#0007`, `#0123`).
- Escolha válida → conversa **aberta**, time atribuído, mensagem com **protocolo** (`display_id`).

## Migração

Após atualizar o código: `rails db:migrate` (coluna `whatsapp_menu_triage_enabled` em `inboxes`).
