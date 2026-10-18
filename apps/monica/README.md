# Monica — instalação local e snapshot criptografado

O Monica continua em MariaDB: a imagem Docker estável v4 suporta oficialmente
MySQL/MariaDB. SQLite não é usado nesta instalação, pois mudaria o banco para
um caminho sem suporte na imagem estável.

## O que é versionado

- A configuração do serviço, atalho de aplicativo, timers e `compose.yaml`.
- `data/database.sql.gz.age`: dump transacional do banco, comprimido e
  criptografado.
- `data/storage.tar.gz.age`: fotos, documentos e chaves de OAuth do Monica,
  também comprimidos e criptografados.
- `data/runtime.env.age`: a chave `APP_KEY` e a credencial interna do banco,
  criptografadas.

Nenhum arquivo de dados em texto puro, senha ou chave privada deve entrar no
Git. A chave privada correspondente fica apenas em
`~/.config/monica/backup-x25519.agekey` com permissão `0600`.

## Sincronização segura

No primeiro envio, confira e versione a configuração e os arquivos `.age`:

```bash
cd ~/Git/dotenv
git add apps/monica
git status
git commit -m "feat(monica): backup criptografado"
```

O timer roda no primeiro dia de cada mês, cria um novo snapshot criptografado,
faz commit somente de `apps/monica/data` e envia ao remoto configurado. Este
repositório é público por decisão do proprietário: apenas os blobs `.age`
criptografados são enviados, nunca chaves privadas, senhas ou dados em texto
puro. Ainda assim, um remoto privado é a opção mais conservadora.

Guarde a identidade `backup-x25519.agekey` fora desta máquina, por exemplo no
gerenciador de senhas como anexo seguro. Ela não vai para o Git; sem ela os
arquivos `.age` não podem ser restaurados.

## Restaurar em outra máquina

1. Clone o repositório e instale o `age` (`nix profile add nixpkgs#age`).
2. Transfira a identidade privada por um canal seguro para
   `~/.config/monica/backup-x25519.agekey` e aplique `chmod 600`.
3. Instale os arquivos do serviço em `~/.local/share/monica` e em
   `~/.config/systemd/user` usando os modelos deste diretório.
4. Decifre `data/runtime.env.age` para `~/.local/share/monica/.env`, suba só o
   serviço `db`, importe `data/database.sql.gz.age` via `mariadb`, restaure
   `data/storage.tar.gz.age` no volume `monica_storage` e então suba `app`.

Os três arquivos precisam ser restaurados juntos; em especial, a `APP_KEY`
preserva dados da instância que possam depender da chave de aplicação.
