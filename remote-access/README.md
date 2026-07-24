# Acesso remoto (MeshCentral + Dashboard App do Chatwoot)

Piloto para substituir o AnyDesk: agente MeshCentral na máquina do cliente,
botão dentro da conversa do Chatwoot que abre o controle remoto no navegador.

Nada aqui toca no código do Chatwoot — o Dashboard App é só configuração em
banco, então não gera conflito nos merges de upstream.

Roda no **mesmo VPS** do Chatwoot (`92.118.59.246`), reaproveitando o Nginx e o
Certbot que já estão no host:

- MeshCentral em `127.0.0.1:4430`, publicado em `mesh.jssystem-server.xyz`
- Página do Dashboard App servida estática em
  `https://app.jssystem-server.xyz/acesso-remoto/` — sem DNS nem certificado
  novos, porque é path no domínio que já existe

## 1. DNS

Um registro A novo:

```
mesh.jssystem-server.xyz  →  92.118.59.246
```

Espere propagar antes de pedir o certificado.

## 2. Subir o MeshCentral

Na VPS, com o conteúdo de `remote-access/` em `/opt/remote-access`:

```bash
cd /opt/remote-access
cp meshcentral-data/config.json.example meshcentral-data/config.json
docker compose up -d
docker compose logs -f meshcentral
```

O `config.json` já vem com o domínio certo. Ele sobe em `TLSOffload`, ou seja,
quem termina o TLS é o Nginx do host.

## 3. Certificado do subdomínio

Chicken-and-egg: o Certbot precisa de um vhost na porta 80 respondendo pelo
subdomínio antes de emitir. Mesmo fluxo do `deploy_vps_production.sh`:

```bash
cat > /etc/nginx/sites-available/meshcentral_http.conf <<'EOF'
server {
  listen 80;
  server_name mesh.jssystem-server.xyz;
  location /.well-known/acme-challenge/ { root /var/www/html; }
  location / { return 404; }
}
EOF

ln -sf /etc/nginx/sites-available/meshcentral_http.conf /etc/nginx/sites-enabled/meshcentral.conf
nginx -t && systemctl reload nginx

certbot certonly --webroot -w /var/www/html -d mesh.jssystem-server.xyz
```

## 4. Vhost definitivo do MeshCentral

```bash
sed 's/__MESH_DOMAIN__/mesh.jssystem-server.xyz/g' \
  /opt/remote-access/nginx_meshcentral.conf.template \
  > /etc/nginx/sites-available/meshcentral.conf

ln -sf /etc/nginx/sites-available/meshcentral.conf /etc/nginx/sites-enabled/meshcentral.conf
rm -f /etc/nginx/sites-available/meshcentral_http.conf
nginx -t && systemctl reload nginx
```

Acesse `https://mesh.jssystem-server.xyz` — a tela de login do MeshCentral tem
que aparecer.

## 5. Servir a página do Dashboard App

```bash
install -d /var/www/acesso-remoto
cp /opt/remote-access/dashboard-app/* /var/www/acesso-remoto/
chmod -R a+rX /var/www/acesso-remoto
```

Agora adicione o `location` no vhost do Chatwoot **que está no ar**:

```
/etc/nginx/sites-available/chatwoot_app.jssystem-server.xyz.conf
```

Copie o bloco `location /acesso-remoto/` de
`deployment/nginx_chatwoot_app.conf.template` (já commitado lá), colando
**antes** do `location /`, e troque `__DOMAIN__` por `app.jssystem-server.xyz`.
Depois `nginx -t && systemctl reload nginx`.

> O template no repo só é renderizado no deploy inicial
> (`deploy_vps_production.sh:197`) — o update zero-downtime não reescreve o
> vhost. Por isso a edição manual agora; o commit no template é para o próximo
> provisionamento do zero sair já correto.

Teste: `https://app.jssystem-server.xyz/acesso-remoto/` deve abrir a página
dizendo que nenhuma máquina está vinculada.

## 6. Criar o admin do MeshCentral

O `config.json` sobe com `newAccounts: true` porque a primeira conta criada vira
admin. **Faça isso imediatamente:**

1. Acesse `https://mesh.jssystem-server.xyz` e crie a conta.
2. Mude `newAccounts` para `false` em `meshcentral-data/config.json`.
3. `docker compose restart meshcentral`

Deixar cadastro aberto em servidor público é convite para conta indevida.

## 7. Grupo de dispositivos e consentimento

No MeshCentral: **My Devices → Add Device Group**. Um grupo por cliente.

Entre no grupo → **Edit** → seção de consentimento e marque **prompt** e
**notificação** para desktop. Isso faz o cliente ver e aprovar a conexão antes
de você entrar, e mostra a barra de sessão ativa.

Não pule. Acesso silencioso ao computador de terceiro é problema de LGPD, e a
aprovação explícita é o que te protege. Vale também ligar gravação de sessão no
grupo para ter trilha de auditoria.

## 8. Instalar o agente no cliente

No grupo do cliente → **Add Agent** → baixe o instalador Windows e rode na
máquina dele. Instala como serviço e conecta de saída — não precisa abrir porta
no firewall do cliente.

## 9. Pegar o node id

Clique no dispositivo no MeshCentral. A barra de endereços fica tipo:

```
https://mesh.jssystem-server.xyz/?viewmode=10&gotonode=ABC123@XYZ...
```

Copie o valor de `gotonode`.

## 10. Configurar no Chatwoot

**Atributo do contato** — Configurações → Atributos Personalizados → Novo:

- Aplica-se a: Contato
- Tipo: Texto
- Chave: `mesh_node_id`

**Dashboard App** — Configurações → Integrações → Dashboard Apps → Novo:

- Título: `Acesso Remoto`
- URL: `https://app.jssystem-server.xyz/acesso-remoto/`

**Vincular a máquina** — abra o contato do cliente e preencha `mesh_node_id`.
Se tiver mais de um PC, separe por vírgula e opcionalmente dê nome:

```
Recepção=ABC123@XYZ, Financeiro=DEF456@UVW
```

## 11. Testar

Abra uma conversa desse contato. A aba **Acesso Remoto** aparece ao lado de
"Mensagens". Clique em **Acessar área de trabalho** — abre em nova aba, o
cliente recebe o prompt de consentimento, e ao aceitar você tem o controle.

## Observações do piloto

- **Concorrência de recursos**: sessão remota relaya vídeo pelo mesmo VPS que
  roda o Chatwoot. Com 1-2 clientes no piloto é tranquilo; se virar rotina com
  várias sessões simultâneas, acompanhe CPU e banda e considere separar.
- **Banco**: MeshCentral usando NeDB (arquivo). Suficiente para o teste; para
  dezenas de máquinas, migre para MongoDB.
- **Backup**: o que importa é `meshcentral-data/`.
- **Renovação do cert**: o Certbot já renova sozinho, mas o hook de reload
  precisa recarregar o Nginx (`systemctl reload nginx`) para o subdomínio novo
  também.
- **Fluidez**: teste com clientes de internet diferentes. É o único ponto que só
  se resolve na rede real.
- **Áudio**: não existe no MeshCentral.

## Divergência de caminho no repo

`deployment/README_DEPLOY_VPS.md` diz que o código fica em `/opt/chatwoot`, mas
o workflow de deploy (`.github/workflows/deploy_production.yml`) roda em
`/home/deploy/chatwoot`. Não afeta este piloto — o stack do MeshCentral é
independente e mora em `/opt/remote-access` — mas vale alinhar os dois docs.
