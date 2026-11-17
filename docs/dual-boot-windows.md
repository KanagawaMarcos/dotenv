# Dual boot Windows 11 + NixOS — runbook reproduzível

Roteiro para (re)fazer o dual boot desta máquina a partir do zero, seja
por uma pessoa ou por uma sessão nova do Claude. Escrito em 2026-11-17.
Contexto de firmware e discos: veja o [README](../README.md),
seções *Estado atual*, *Firmware: a BIOS reescreve a BootOrder* e
*Dual boot com Windows*.

> **Para o Claude numa sessão nova:** leia este arquivo inteiro e o
> README antes de agir. Os comandos que precisam de root o usuário roda
> com `! pkexec $(command -v <cmd>) ...`, porque `sudo` sem TTY falha.
> Para aplicar a config, o usuário roda `nixos build` num terminal próprio
> (= `nixos-rebuild switch --flake ~/Git/dotenv#nixos`); daqui, use
> `! pkexec $(command -v nixos-rebuild) switch --flake /home/kanagawamarcos/Git/dotenv#nixos`.

## Objetivo e princípios

- **O NixOS é o sistema principal.** Tudo que importa vive nele e é
  declarado neste repositório. O bootloader é dele (Lanzaboote).
- **O Windows é descartável.** Serve só para jogos com anti-cheat
  (Battlefield 6/Javelin, que exige Secure Boot + TPM 2.0) e softwares
  fechados. **Nada importante é salvo nele**, então pode ser apagado e
  reinstalado sem backup. Consequências práticas:
  - BitLocker **desligado** (não há o que proteger, e ele só traz risco
    de pedir chave de recuperação a cada mudança no boot).
  - Fast Startup **desligado** (dual boot).
  - Reinstalar o Windows é um procedimento normal: veja *Reinstalar só o
    Windows*, logo abaixo.
- **O Secure Boot fica sempre ligado**, com chaves próprias + Microsoft.
  Os dois sistemas bootam com ele ligado. Só se desliga temporariamente
  para bootar o pen drive (Ventoy/ISO do NixOS não são assinados para
  estas chaves).

## Estado atual (2026-11-17): dual boot ✅, Secure Boot ligado ✅

| | Disco "NixOS" | Disco "Windows" (ex-`storage`) |
|---|---|---|
| Serial | `C1D307021B0901178259` | `TPBF2007240030400210` |
| Partições | ESP vfat 1G `4587-D4ED` (`/boot`) + ext4 raiz | `Microsoft reserved` 16M + NTFS (sem ESP) |
| Bootloaders na ESP | systemd-boot assinado (Lanzaboote) em `\EFI\BOOT\BOOTX64.EFI` **e** Windows em `\EFI\Microsoft\Boot\bootmgfw.efi` | — |
| Raiz | ext4 UUID `aa310bed-f9ca-4925-86be-78077712946a` | NTFS UUID `226A1DC16A1D9321` |

- **A ESP do NixOS é compartilhada com o Windows.** É o layout testado
  e é o que permite o systemd-boot listar o Windows sozinho, sem
  os-prober. Menu: 10 s, editor de cmdline desligado
  (`configuration.nix`, blocos `boot.loader` e `boot.lanzaboote`).
  **Não reformate essa ESP sem antes salvar o `\EFI\Microsoft\`.**
- Secure Boot: `bootctl status` → `Secure Boot: enabled (user)`;
  `sbctl status` → `Vendor Keys: microsoft`. Chaves em `/var/lib/sbctl`
  (**fora do Git**). Driver NVIDIA ok com Secure Boot.
- No Windows: Fast Startup e BitLocker **desligados** (conferido).
- Relógio: `time.hardwareClockInLocalTime = true` na config.
- O `/mnt/storage` não existe mais. A partição `Microsoft reserved`
  ainda carrega o UUID ext4 antigo `4a99c463-...`: **nunca monte esse UUID**.
- Pendências: passos 10–12 do checklist da seção 6 (conferir o
  `msinfo32`, testar o BF6 e limpar os restos do GRUB).

> 🚨 Os nomes `nvme0n1` e `nvme1n1` **trocam entre boots**. Sempre
> identifique os discos por serial ou UUID:
> ```bash
> lsblk -o NAME,SIZE,SERIAL,PARTUUID,UUID,FSTYPE,LABEL,MOUNTPOINTS
> lsblk -no PKNAME $(findmnt -no SOURCE /)   # disco do NixOS neste boot
> ```

## Refazer tudo do zero (ordem recomendada)

Para uma máquina limpa, ou depois de perder o disco do NixOS. Cada passo
aponta para a seção com os detalhes. Os passos 4–7 foram feitos de
verdade em 2026-11-17. O passo 3 com Lanzaboote desde a instalação é a
adaptação recomendada, **ainda não testada** (na época o NixOS já estava
instalado com GRUB).

1. **Pen drive** com Ventoy + ISO do NixOS + ISO do Windows (seção 1).
2. **BIOS** (caminho exato na seção 6, box *BIOS da Biostar B550GTA*):
   Secure Boot **Disabled**, CSM **Disabled**, TPM (Security Device
   Support) **Enabled**. Se houver chaves antigas: Security → Secure Boot →
   Key Management → **Reset To Setup Mode**.
3. **Instalar o NixOS** no disco `C1D307021B0901178259`, seguindo o README
   (*Instalação em UEFI*): GPT, ESP vfat de **1G** em `/boot`, ext4 na raiz.
   Como a config usa Lanzaboote, **as chaves precisam existir antes do
   `nixos-install`**. No live, depois de montar em `/mnt` (⚠️ não testado):
   ```bash
   sudo mkdir -p /mnt/var/lib/sbctl /var/lib/sbctl
   sudo mount --bind /mnt/var/lib/sbctl /var/lib/sbctl
   sudo nix --extra-experimental-features 'nix-command flakes' \
     shell nixpkgs#sbctl -c sbctl create-keys    # grava em /mnt/var/lib/sbctl
   git clone <este repo> /mnt/home/kanagawamarcos/Git/dotenv
   # Ajuste os UUIDs do hardware-configuration.nix (nixos-generate-config).
   sudo nixos-install --flake /mnt/home/kanagawamarcos/Git/dotenv#nixos
   ```
   Alternativa, se der problema: instalar com a config mínima do README
   (sem Lanzaboote), bootar, rodar `sbctl create-keys` e só então trocar
   para a config deste repo com `nixos build` (foi o caminho usado em
   2026-11-17, partindo do GRUB).
4. **Instalar o Windows** no outro disco, `TPBF2007240030400210`, com o
   **disco do NixOS visível** (seção 2). O instalador reaproveita a ESP do
   NixOS e o systemd-boot passa a listar o Windows sozinho.
5. **Voltar ao NixOS** pelo menu (seção 3) e conferir
   `! pkexec $(command -v sbctl) verify`. Se o `BOOTX64.EFI` tiver sido
   trocado pelo Windows, rode `nixos build`. O Lanzaboote reinstala o
   systemd-boot quando o arquivo não é assinado pelas nossas chaves.
6. **Registrar as chaves e ligar o Secure Boot**: seção 6, passos 6–9
   (`sbctl enroll-keys --microsoft`, depois Secure Boot **Enabled** na BIOS).
7. **No Windows**: Fast Startup e BitLocker desligados (seção 2, passo 4);
   `msinfo32` com a inicialização segura *Ativada*; testar o jogo
   (seção 6, passos 10–11).

## Reinstalar só o Windows

O Windows não guarda nada importante, então é só apagar e reinstalar:

1. BIOS: Security → Secure Boot → **Disabled** (as chaves continuam
   registradas; só é preciso para o pen drive bootar).
2. F11 → pen drive → Ventoy → Windows. No instalador, apague **só** as
   partições do disco `TPBF2007240030400210` (Microsoft reserved + NTFS) e
   instale no espaço livre. ⚠️ **Não apague nada do outro disco**: a ESP
   de 1G dele é a do NixOS (e também a do Windows).
3. O instalador recria `\EFI\Microsoft\` na ESP do NixOS. Em 2026-11-17
   ele **não** mexeu no `\EFI\BOOT\BOOTX64.EFI`. Se o PC passar a ir
   direto para o Windows, siga a seção 5.
4. No NixOS: `! pkexec $(command -v sbctl) verify`. Se algo do NixOS
   aparecer como não assinado, rode `nixos build`.
5. BIOS: Secure Boot → **Enabled**. Confira no NixOS com `bootctl status`.
6. No Windows: Fast Startup off, BitLocker off (seção 2, passo 4).

## Histórico: como foi feito em 2026-11-17

As seções 0–5 abaixo registram o caminho percorrido (Ventoy → Windows →
GRUB + os-prober → Lanzaboote). Onde o plano original divergiu do que
deu certo, o texto diz qual vale. A seção 6 (Secure Boot) é a referência
atual do bootloader.

## 0. Antes de começar

- [ ] Nada a salvar no disco do Windows (ele é descartável). Se o disco
      de destino tiver outra coisa, faça backup: o instalador apaga tudo.
- [ ] Anote o serial do disco do NixOS (tabela acima) para reconhecê-lo
      na BIOS ou na etiqueta.
- [ ] Secure Boot **desligado** durante a instalação, para o pen drive
      bootar. O Win11 exige UEFI + TPM 2.0, mas o instalador não exige
      Secure Boot.

## 1. Pen drive com Ventoy (Windows + NixOS)

O Ventoy instala um bootloader no pen drive uma vez. Depois disso basta
copiar as `.iso` para a partição exFAT, e ele mostra um menu na hora do
boot. Ele ocupa só ~32 MB (partição `VTOYEFI`).

```bash
# 1. Ventoy do nixpkgs (marcado como unfree + inseguro por ter blobs binários)
NIXPKGS_ALLOW_UNFREE=1 NIXPKGS_ALLOW_INSECURE=1 \
  nix build --impure nixpkgs#ventoy -o /tmp/ventoy
readlink -f /tmp/ventoy/bin/ventoy           # caminho no /nix/store

# 2. Identifique o pen drive (TRAN=usb, RM=1) e desmonte as partições dele
lsblk -o NAME,SIZE,TYPE,TRAN,RM,MODEL,LABEL
udisksctl unmount -b /dev/sdX1

# 3. Instale (APAGA o pen drive). Rodado pelo usuário:
#    ! printf 'y\ny\n' | pkexec /nix/store/...-ventoy-X/bin/ventoy -I /dev/sdX

# 4. Monte a partição "Ventoy" e copie as ISOs
udisksctl mount -b /dev/sdX1
cp ~/Downloads/Windows11_*.iso ~/Downloads/nixos-graphical-*.iso \
   /run/media/$USER/Ventoy/ && sync
```

Feito em 2026-11-17 com Ventoy 1.1.12, num pen drive de 14,5 GiB:
Windows 11 (26300, 8,4 GiB) + NixOS 26.05 graphical (3,6 GiB), com
~2,4 GB livres.

Por que **não** tem Boot-Repair-Disk no pen drive:

- O Boot-Repair é feito para GRUB de Ubuntu: roda `grub-install` e
  `update-grub` dentro do sistema instalado. No NixOS, na melhor das
  hipóteses ele falha. Na pior, instala um GRUB fora do controle do
  NixOS. **Não usar.**
- A ISO do NixOS faz o papel dele (seção 5).
- As três ISOs (Windows + NixOS + Boot-Repair, 14,5 GiB) não cabiam em
  14,4 GiB. Testamos encolher a ISO do Windows exportando só Pro + Home
  para `install.esd` LZMS (8,16 → 5,77 GB). Funciona, mas obriga a
  remontar a ISO com UDF, e há relato de crash do Setup 24H2+ com ESD
  gerado pelo wimlib. Descartado.

Pontos do Ventoy:

- A 1.1.12 tem bugs de Secure Boot que foram corrigidos na 1.1.14 e na
  1.1.18. Não afetam esta máquina enquanto o Secure Boot estiver
  desligado. Se for ligá-lo, use um Ventoy mais novo (direto do GitHub,
  caso o nixpkgs não tenha).
- Builds Insider 26xxx às vezes só bootam no modo **wimboot** do Ventoy.
  Se o Windows não iniciar no modo normal, escolha o wimboot no menu.

## 2. Instalar o Windows

1. **Decida o layout da ESP:**
   - **A, ESP compartilhada (recomendado, é o que está em uso):** deixe
     o disco do NixOS **visível**. O instalador grava o bootloader do
     Windows em `\EFI\Microsoft\` da ESP do NixOS, e o systemd-boot do
     Lanzaboote lista o Windows sozinho. Risco: uma instalação ou
     atualização grande do Windows pode sobrescrever o
     `\EFI\BOOT\BOOTX64.EFI`. Isso não aconteceu em 2026-11-17, e a
     correção está na seção 5.
   - **B, uma ESP por disco:** **desative o disco do NixOS** na BIOS ou
     desconecte-o (serial `C1D307021B0901178259`) antes do instalador.
     Os sistemas ficam independentes, mas o systemd-boot **não** enxerga
     ESPs de outros discos: o Windows só boota pelo F11 (ou exigiria uma
     entrada com `edk2-uefi-shell`). Era o plano original; não foi testado
     com o Lanzaboote.
2. Boote pelo pen drive (**F11** = menu de boot da placa) → Ventoy →
   Windows.
3. Instale no disco `TPBF2007240030400210`: apague **só** as partições
   dele e deixe o instalador criar as dele. No layout A ele cria só MSR +
   NTFS e usa a ESP do outro disco. No layout B ele cria ESP + MSR + NTFS
   + recovery. Se no layout B ele **não** criar a ESP, é porque está
   enxergando a do outro disco: o disco do NixOS não foi desativado de
   verdade.
4. Já no Windows, no primeiro boot (pós-instalação):

   | Item | Necessidade | Status |
   |---|---|---|
   | Fast Startup desligado | **Obrigatório** em dual boot | ✅ desligado |
   | BitLocker | **Manter desligado** (Windows descartável, nada a proteger) | ✅ desligado |
   | Relógio (RTC) | Nada a fazer: já tratado no NixOS | ✅ |

   - **Fast Startup.** Com ele ligado, "Desligar" no Windows na verdade
     **hiberna** o kernel e deixa o NTFS num estado "em uso". Se o Linux
     escrever nesse disco, o Windows acorda sem saber das mudanças e
     arquivos podem ser corrompidos. O NixOS normalmente recusa ou monta
     só leitura. O Windows também pode deixar Wi-Fi, Bluetooth etc. num
     estado estranho para o outro sistema.
     Como desligar: Painel de Controle → Opções de Energia → *Escolher a
     função dos botões de energia* → *Alterar configurações não
     disponíveis no momento* → desmarcar **Ligar inicialização rápida**.
     Para desligar também a hibernação, rode no PowerShell como admin:
     `powercfg /h off`.
   - **BitLocker / criptografia do dispositivo.** O Win11 24H2+ liga
     sozinho quando se entra com conta Microsoft. O TPM só libera o disco
     se o caminho de boot medido for o mesmo de sempre. **Nesta máquina o
     risco é maior que o normal**: o Windows boota via chainload do
     systemd-boot (antes, do GRUB) a partir de uma ESP compartilhada com
     o NixOS. Atualizar o bootloader, trocar as chaves do Secure Boot,
     mexer na BIOS ou alternar entre o menu do NixOS e o F11 pode fazer o Windows
     pedir a **chave de recuperação** de 48 dígitos. Sem ela, os dados do
     Windows ficam inacessíveis.
     - Conferir: Configurações → Privacidade e segurança → *Criptografia
       do dispositivo*, ou `manage-bde -status` no terminal admin.
     - Se estiver ligada: a chave fica em
       <https://account.microsoft.com/devices/recoverykey>. Guarde uma
       cópia fora do PC, por exemplo no gerenciador de senhas. **Não
       versione a chave neste repositório** (política do `AGENTS.md`).
     - Se o pedido da chave virar rotina a cada boot pelo menu, existem
       duas saídas: suspender e reativar a proteção pelo Windows
       (`manage-bde -protectors -disable C:` e depois `-enable`), para o
       TPM aprender o caminho novo, ou desligar a criptografia.
   - **Relógio.** O Windows guarda o RTC em horário local e o Linux em
     UTC; sem ajuste, a hora pularia 3h a cada troca. Já está resolvido
     pelo `time.hardwareClockInLocalTime = true` no NixOS. A alternativa
     inversa é o Windows em UTC (`RealTimeIsUniversal=1` no registro) e
     remover essa opção do NixOS. As duas funcionam, não misture.

## 3. Voltar para o NixOS

1. Reative ou reconecte o disco do NixOS.
2. Se a placa bootar direto no Windows: com uma ESP por disco, os dois
   discos têm um `\EFI\BOOT\BOOTX64.EFI`, e a placa pode escolher o do
   Windows. (Com a ESP compartilhada, como hoje, isso não acontece.)
   - **F11** → escolha o NVMe do NixOS.
   - Na BIOS, coloque o NVMe do NixOS em primeiro na **prioridade de
     discos**. Não adianta usar o `efibootmgr -o`, porque esta placa
     reescreve a BootOrder (veja o README).

## 4. Ajustar a config do NixOS (fase GRUB, histórico)

> Esta seção registra como foi feito com GRUB + os-prober, antes do
> Lanzaboote. Hoje o bootloader é o da seção 6 e o Windows aparece no
> menu sem os-prober. Os passos 1–2 continuam valendo.

1. **Remova o volume `storage`** do `configuration.nix`: o bloco
   `fileSystems."/mnt/storage"` e o serviço `systemd.services.storage-owner`.
   ✅ feito no commit `4e2dac2`. Não basta confiar no `nofail`: o UUID
   antigo sobrevive na partição `Microsoft reserved`.
2. Atualize o README: o disco "Storage" virou "Windows". ✅ feito.
3. Aplique (num terminal próprio, porque usa `sudo` e pede senha):
   ```bash
   nixos build
   ```
   Isso roda o `os-prober` e reescreve o `grub.cfg`. Não precisa de
   `--install-bootloader`, porque nada no binário do GRUB mudou.
4. Confira:
   ```bash
   sudo grep -i -A3 'windows' /boot/grub/grub.cfg   # /boot é só do root
   # esperado: menuentry 'Windows Boot Manager (on /dev/nvmeXn1p1)' ...
   ```
5. Reinicie: o GRUB deve listar NixOS e Windows. Teste os dois.
6. Commit e push (política do `AGENTS.md`).

### Se o os-prober não achar o Windows

Adicione uma entrada manual, apontando pelo UUID da ESP que contém
`\EFI\Microsoft\` (hoje é a própria ESP do NixOS, `4587-D4ED`; com uma
ESP por disco, é a vfat "EFI System" do disco do Windows, que aparece em
`lsblk -o NAME,UUID,FSTYPE,PARTTYPENAME`):

```nix
boot.loader.grub.extraEntries = ''
  menuentry "Windows 11" {
    insmod part_gpt
    insmod fat
    search --no-floppy --fs-uuid --set=root XXXX-XXXX
    chainloader /EFI/Microsoft/Boot/bootmgfw.efi
  }
'';
```

## 5. Recuperação: o menu do NixOS sumiu

Sintoma: a máquina vai direto para o Windows mesmo escolhendo o disco do
NixOS no F11. Na ESP do NixOS o `\EFI\BOOT\BOOTX64.EFI` (systemd-boot do
Lanzaboote) foi sobrescrito. Acontece quando o Windows usa a ESP do
NixOS, como hoje, e uma instalação ou uma atualização grande grava o
fallback dele ali.

0. **Desligue o Secure Boot na BIOS primeiro.** A ISO do NixOS e o
   Ventoy 1.1.12 não são assinados para as chaves registradas nesta
   placa e não bootam com ele ligado. As chaves continuam no firmware.
   Depois de consertar, é só religar.
1. Boote pelo pen drive → Ventoy → NixOS (live).
2. Monte **pelo UUID** (os nomes de device trocam):
   ```bash
   sudo mount /dev/disk/by-uuid/aa310bed-f9ca-4925-86be-78077712946a /mnt
   sudo mount /dev/disk/by-uuid/4587-D4ED /mnt/boot
   ```
3. Reinstale o bootloader a partir da geração atual. O Lanzaboote assina
   com as chaves de `/mnt/var/lib/sbctl`, que estão no disco do NixOS:
   ```bash
   sudo nixos-enter --root /mnt -c \
     'NIXOS_INSTALL_BOOTLOADER=1 /nix/var/nix/profiles/system/bin/switch-to-configuration boot'
   ```
   A saída precisa conter `Installing /boot/EFI/BOOT/BOOTX64.EFI` e
   `Successfully installed Lanzaboote`.
4. Confira antes de reiniciar:
   ```bash
   sudo grep -a -m1 -oiE 'grub|systemd-boot' /mnt/boot/EFI/BOOT/BOOTX64.EFI   # "systemd-boot"
   sudo nixos-enter --root /mnt -c 'sbctl verify'   # BOOTX64.EFI e EFI/Linux/*.efi assinados
   ```
5. Se a ESP do NixOS tiver sido **apagada ou reformatada**, recrie com
   `mkfs.fat -F32 -i 4587D4ED` para manter o UUID que o
   `hardware-configuration.nix` espera. Depois repita os passos 2–4.
   ⚠️ Isso também apaga o bootloader do Windows (`\EFI\Microsoft\`).
   Antes de reformatar, copie essa pasta, se ela ainda existir, e
   devolva-a depois. Se não der, conserte pelo pen drive do Windows
   (Reparar → Prompt): `bcdboot C:\Windows /s <letra-da-ESP>: /f UEFI`.

Rede de segurança extra (só com Secure Boot desligado): enquanto não for
limpo, o GRUB antigo está salvo em `\EFI\grub-backup\BOOTX64.EFI`, com o
`grub.cfg` e os kernels em `/boot/grub` e `/boot/kernels`. Para voltar a
ele, copie esse arquivo por cima de `\EFI\BOOT\BOOTX64.EFI`. Ele boota as
gerações listadas no `grub.cfg` do último `nixos build` com GRUB.

## 6. Secure Boot com Lanzaboote

Objetivo: Secure Boot **sempre ligado**, com os dois sistemas bootando.
O Battlefield 6 (anti-cheat Javelin) exige Secure Boot + TPM 2.0 no
Windows. Com o GRUB isso era impossível, porque ele não é assinado.

### Como funciona

- O [Lanzaboote](https://github.com/nix-community/lanzaboote) (v1.2.0,
  input `lanzaboote` no `flake.nix`) gera uma **UKI** por geração
  (`\EFI\Linux\nixos-generation-N-*.efi`) e um systemd-boot, ambos
  **assinados com chaves próprias** em `/var/lib/sbctl`.
- As chaves são registradas no firmware **junto com as da Microsoft**
  (`--microsoft`). Assim o firmware aceita o systemd-boot e as UKIs
  (assinados pelas nossas chaves), o `bootmgfw.efi` do Windows e a option
  ROM da NVIDIA (assinados pela Microsoft).
- Conferido no código do lzbt (`rust/tool/systemd/src/install.rs`): ele
  instala o systemd-boot assinado em `\EFI\BOOT\BOOTX64.EFI` **e** em
  `\EFI\systemd\`, e não escreve na NVRAM. Por isso a manha da placa (que
  sempre boota o `BOOTX64.EFI`) continua resolvida, e o
  `canTouchEfiVariables = false` continua valendo.
- O `sbctl verify` mostra ✗ em `EFI/Microsoft/*` e em
  `EFI/nixos/kernel-*.efi`. **É esperado**: os do Windows são assinados pela
  Microsoft, e os kernels são verificados por hash pela UKI assinada.
- 🔐 **As chaves privadas em `/var/lib/sbctl` NUNCA vão para o Git.**
  Se o disco do NixOS for perdido, gere chaves novas e registre de novo
  (com o Secure Boot desligado, a placa em Setup Mode e `enroll-keys
  --microsoft`).

### Checklist (para refazer do zero, na ordem)

| # | Passo | Comando / onde | Status (2026-11-17) |
|---|---|---|---|
| 1 | Backup do bootloader antigo | `! pkexec $(command -v install) -D -m644 /boot/EFI/BOOT/BOOTX64.EFI /boot/EFI/grub-backup/BOOTX64.EFI` | ✅ |
| 2 | Criar as chaves | `! pkexec $(command -v sbctl) create-keys` (antes de aplicar a config, use o sbctl de `nix build nixpkgs#sbctl`) | ✅ |
| 3 | Aplicar a config com Lanzaboote | `nixos build`, ou `! pkexec $(command -v nixos-rebuild) switch --flake ~/Git/dotenv#nixos`. A saída precisa ter `Installing /boot/EFI/BOOT/BOOTX64.EFI` | ✅ |
| 4 | Conferir as assinaturas | `! pkexec $(command -v sbctl) verify`: `BOOTX64.EFI`, `systemd-bootx64.efi` e `EFI/Linux/*.efi` assinados | ✅ |
| 5 | Reboot **com o Secure Boot desligado** e testar | menu do systemd-boot com as gerações + "Windows Boot Manager"; entrar nos dois | ✅ NixOS e Windows ok |
| 6 | Placa em Setup Mode | `sbctl status` → `Setup Mode: ✗ Enabled`. Esta placa veio **sem chaves** (PK/KEK/db/dbx vazios). Se tiver chaves, na BIOS: Security → Secure Boot → Key Management → **Reset To Setup Mode** (a B550GTA não tem "Factory Key Provision"; em outras placas, deixe essa opção **Disabled**) | ✅ já estava |
| 7 | Registrar as chaves | `! pkexec $(command -v sbctl) enroll-keys --microsoft` → `Enrolled keys to the EFI variables!`. ⚠️ **Nunca sem `--microsoft`**: o Windows e a GPU deixariam de bootar. Depois, `sbctl status` mostra `Vendor Keys: microsoft` e aparecem as variáveis `PK`/`KEK`/`db` em `/sys/firmware/efi/efivars`. O "Setup Mode" só muda depois de reiniciar | ✅ |
| 8 | Ligar o Secure Boot | BIOS da B550GTA, caminho no box abaixo | ✅ |
| 9 | Conferir no NixOS | `bootctl status` → `Secure Boot: enabled (user)`; `sbctl status` → `Setup Mode: ✓ Disabled`, `Secure Boot: ✓ Enabled`. Driver NVIDIA 595 carrega normal (o kernel do NixOS não ativa lockdown, então módulos fora da árvore não são barrados) | ✅ |
| 10 | Conferir no Windows | `msinfo32` → Estado da Inicialização Segura **Ativado**; `tpm.msc` → TPM 2.0 pronto | ⬜ |
| 11 | Testar o BF6 | Primeiro entrando pelo menu do systemd-boot. Se o Javelin disser "Secure Boot não ativado", reinicie e entre por **F11 → Windows Boot Manager** (direto do firmware, sem chainload) | ⬜ |
| 12 | Limpeza | Apagar `/boot/loader/entries/nixos-generation-{1,2,3}.conf` (entradas velhas do systemd-boot, não assinadas), `\EFI\NixOS-boot\`, `/boot/grub`, `/boot/kernels` e, por último, `\EFI\grub-backup\` | ⬜ |

### BIOS da Biostar B550GTA: caminho exato (passo 8)

Fonte: manual oficial *BIOS User Guide B550GTA*
(<https://www.biostar-europe.com/upload/Manual/AB55A-A4T_BIOS_200703.pdf>),
seções 2 (Advanced) e 5 (Security). BIOS desta máquina: AMI, versão 5.17,
de 2025-08-31.

**Esta placa NÃO tem "Secure Boot Mode" (Standard/Custom) nem "Factory
Key Provision".** O menu é este:

1. **Advanced → CSM Configuration → CSM Support: `Disabled`** (o padrão de
   fábrica é *Enabled*). O manual diz que o Secure Boot só ativa com o CSM
   desligado. A RTX 3070 Ti tem GOP UEFI, então a imagem continua.
2. **Advanced → Trusted Computing → Security Device Support: `Enabled`**
   (padrão). É o TPM (fTPM da AMD). `bootctl status` já mostra
   `TPM2 Support: yes`.
3. **Security → Secure Boot → Secure Boot: `Enabled`.** Segundo o manual,
   ele só ativa se a PK estiver registrada e a placa estiver em *user mode*,
   o que o passo 7 garante.
4. **Key Management** só aparece com o Secure Boot em *Enabled*. Opções:
   - **Restore Factory keys**: ⚠️ **NÃO usar.** Grava as chaves de fábrica
     (só Microsoft) por cima das nossas, e o NixOS para de bootar.
   - **Reset To Setup Mode**: apaga todas as chaves (PK/KEK/db/dbx). Use
     só para refazer o passo 7.
   - PK / KEK / Authorized Signatures (db) / Forbidden Signatures (dbx):
     Details / Export / Update / Append / Delete. Dá para conferir em
     *Details* que a PK é a nossa (GUID do dono
     `4a3a1b59-2e0d-497f-a447-3899504c91b7`, de `sbctl status`).
5. **F10** para salvar e sair.

Se o NixOS não bootar ("Secure Boot Violation"): volte em Security →
Secure Boot: `Disabled`, boote o NixOS, rode `sbctl status` e confira se
as chaves ainda são as nossas. Se não forem, faça Reset To Setup Mode e
refaça o passo 7.

### Riscos e observações

- **BF6 e chainload:** um relato no fórum da EA (não oficial) diz que o
  Javelin falha quando o Windows é bootado por outro bootloader (GRUB/shim),
  mesmo com o Secure Boot ligado, e mostra a mesma mensagem genérica de
  "Secure Boot não ativado". Não há relato específico sobre o systemd-boot.
  Se acontecer, use o F11 → Windows Boot Manager para jogar.
- **Chaves próprias + Microsoft com o BF6:** não há confirmação oficial. Um
  relato no fórum do CachyOS com essa mesma configuração diz que funcionou
  ("gaming comfortably"), sem citar o jogo.
- **dbx vazio:** a placa veio sem dbx, e o `sbctl --microsoft` não preenche
  a dbx. Isso deixa o firmware sem a lista de bootloaders revogados. Com
  a KEK da Microsoft registrada, o Windows Update consegue aplicar
  atualizações da dbx. Para conferir:
  `ls -l /sys/firmware/efi/efivars/dbx-*`.
- **BitLocker:** desligado hoje. Se ligar, faça isso **depois** do passo 8,
  para o TPM medir o caminho de boot já com o Secure Boot ligado, e
  guarde a chave de recuperação (seção 2, passo 4).
- **Ventoy com Secure Boot:** a 1.1.12 tem bugs de Secure Boot e o pen
  drive não boota com as chaves desta placa. Para usar o pen drive,
  desligue o Secure Boot temporariamente.
- **Para desfazer tudo:** desligue o Secure Boot na BIOS (as chaves podem
  ficar). Para voltar ao GRUB: reverta o commit do Lanzaboote, rode
  `nixos build` e copie `\EFI\grub-backup\BOOTX64.EFI` para
  `\EFI\BOOT\BOOTX64.EFI`, ou rode o `switch-to-configuration boot` com
  `NIXOS_INSTALL_BOOTLOADER=1`.

## Estado real após a instalação (2026-11-17)

Instalado e funcionando. Na fase GRUB, ele listou NixOS + Windows após `nixos build`
(`Found Windows Boot Manager on /dev/nvme0n1p1@/EFI/Microsoft/Boot/bootmgfw.efi`).

O que saiu diferente do plano:

- **O disco do NixOS estava visível durante a instalação.** Por isso o
  Windows **não criou ESP própria**: gravou o bootloader em
  `\EFI\Microsoft\` da **ESP do NixOS** (`4587-D4ED`). O disco do Windows
  ficou só com `Microsoft reserved` (16M) + NTFS. O `\EFI\BOOT\BOOTX64.EFI`
  (GRUB) **não** foi sobrescrito.
- Consequências:
  - O Windows **só boota com o disco do NixOS presente** (pelo menu do NixOS, ou
    F11 → "Windows Boot Manager"). Se o disco do NixOS for removido ou a
    ESP reformatada, o Windows precisa de reparo (`bcdboot` a partir da
    mídia do Windows).
  - Grandes atualizações do Windows podem mexer na ESP do NixOS. Se o
    menu do NixOS sumir, siga a seção 5.
  - **Não reformate a ESP do NixOS** sem antes copiar `\EFI\Microsoft\`.
- A partição `Microsoft reserved` de 16M **herdou a assinatura ext4 do
  antigo `storage`** (UUID `4a99c463-...`, label `storage`). O
  `fileSystems."/mnt/storage"` foi removido do `configuration.nix` para
  não montá-la. Não reutilize esse UUID.
- Esse resultado "acidental" virou o layout recomendado (seção 2,
  layout A), porque com o Lanzaboote/systemd-boot a ESP compartilhada é
  o que faz o Windows aparecer no menu. Para discos 100% independentes
  (layout B), desative o NVMe do NixOS na BIOS de verdade, ou desconecte,
  e confira no instalador do Windows que só um disco aparece.

## Fontes consultadas (2026-11-17)

- Ventoy: <https://www.ventoy.net/en/doc_news.html>,
  <https://github.com/ventoy/Ventoy/issues/2769>
- NixOS: <https://wiki.nixos.org/wiki/Dual_Booting_NixOS_and_Windows>,
  <https://wiki.nixos.org/wiki/Bootloader>
- Recuperar o bootloader:
  <https://discourse.nixos.org/t/how-do-i-rebuild-the-nixos-bootloader-from-windows/48873>
- Boot-Repair: <https://help.ubuntu.com/community/Boot-Repair>
- Instalador do Windows numa ESP de outro disco:
  <https://www.elevenforum.com/t/why-does-bootloader-always-get-messed-up-when-dual-boot-installing-on-another-drive.47813/post-755923>
- wimlib: <https://wimlib.net/man1/wimexport.html>
- Lanzaboote: <https://nix-community.github.io/lanzaboote/getting-started/prepare-your-system.html>,
  <https://nix-community.github.io/lanzaboote/getting-started/enable-secure-boot.html>
- BF6/Javelin e chainload (relato de usuário):
  <https://forums.ea.com/discussions/battlefield-6-technical-issues-en/bf6-secureboot-is-not-enabled-but-it-is-enabled-%E2%80%94-dual-bootgrub-is-the-cause/13568958>
- sbctl + Microsoft keys em dual boot com Javelin (relato de usuário):
  <https://discuss.cachyos.org/t/issues-enabling-secure-boot-on-gigabyte-motherboard-for-dual-boot-windows-11-battlefield-6-javelin-anticheat/23444>
