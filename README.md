# dotenv — config NixOS do Marcos

Config do sistema. Atualizada em **2026-09-14**.

> ⚠️ **Esta config assume instalação em UEFI.** Se você colar isto numa
> instalação BIOS/Legacy, **a máquina não dá boot.**

| | Máquina antiga | Atual |
|---|---|---|
| NixOS | 25.11 | **26.05 (Yarara)** |
| Boot | UEFI + systemd-boot | **UEFI + GRUB** (`device = "nodev"`) |
| Desktop | KDE Plasma 6 + SDDM | **Pantheon + LightDM** |
| GPU | NVIDIA (`open = false`) | NVIDIA GA102, driver 595 (**`open = true`**) |
| Swap | partição | **zram** |
| Dual boot | — | Windows em disco separado, ESP própria |

Hardware: Biostar B550GTA (BIOS 5.17), AMD, NVIDIA GA102 (RTX 30xx),
2× NVMe de 1TB. Desktop.

---

## Estado atual — instalado em 2026-09-14 ✅

A reinstalação em UEFI **foi feita e conferida**. Fase 1 concluída.

> 🚨 **NUNCA identifique os discos por `nvme0n1` / `nvme1n1`.** Foi
> observado na prática: entre dois boots da mesma máquina, sem mexer em
> hardware, os dois NVMe **trocaram de nome**. Num boot o NixOS estava
> no `nvme0n1`, no seguinte no `nvme1n1`. Os dois têm 953,9G, então não
> dá pra distinguir nem pelo tamanho. Use sempre PARTUUID/UUID.

Os dois discos são **TEAM TM8FP4001T de 953,9G**, idênticos. O que os
distingue de verdade é o serial (visível na etiqueta, útil na hora de
desconectar um pra instalar o Windows) e os UUID:

| Papel | Serial do disco | ESP (PARTUUID / UUID) | root (UUID) |
|---|---|---|---|
| **NixOS** | `C1D307021B0901178259` | `a815cf7c-7067-4a6d-898f-3683c6243969` / `4587-D4ED` | `aa310bed-f9ca-4925-86be-78077712946a` (ext4 952,9G) |
| **Livre — vai virar Windows** | `TPBF2007240030400210` | `ce83cee5-d9a6-48fa-89f4-3f006f6711d3` / `5598-8A92` | `cffb5b77-72ea-4192-853e-a1f9ef523bf9` (Ubuntu 26.04 antigo, ext4 952,8G) |

Para saber qual é qual **no boot atual**:

```bash
lsblk -o NAME,SIZE,PARTUUID,UUID,FSTYPE,MOUNTPOINT
findmnt -no SOURCE /     # o disco deste device é o do NixOS
```

Os UUID acima são os mesmos do `hardware-configuration.nix` — esse é o
vínculo confiável, e é por isso que o NixOS monta por UUID e não por
nome de device.

Confirmado na máquina:

- `/sys/firmware/efi/efivars` existe → **UEFI de verdade**
- `nixos-version` → `26.05.9592 (Yarara)`, `system.stateVersion = "26.05"`
- ESP tipo *EFI System*, vfat, montada em `/boot` (40M de 1022M usados)
- `fileSystems."/boot"` presente no `hardware-configuration.nix`
  (o erro nº1 de instalação UEFI **não** aconteceu)

Config do repo aplicada e **bootada com sucesso** (geração 5), tudo
verificado na máquina:

| Check | Resultado |
|---|---|
| Bootloader | GRUB (`BOOT_IMAGE=(hd0,gpt1)`; as vars EFI do systemd-boot sumiram) |
| NVIDIA | 595.71.05, módulos `nvidia/nvidia_drm/nvidia_modeset/nvidia_uvm` carregados, RTX 3070 Ti (GA102) |
| Sessão | Pantheon **Wayland** (`pantheon-wayland`), gala usando a GPU NVIDIA |
| zram | `/dev/zram0`, 31,4G, prio 5 |
| Serviços | docker, bluetooth, cups, avahi, lightdm — todos `active` |
| Gaming | steam, gamescope, gamemoded, mangohud, lutris, heroic, godot |
| Grupos | `wheel uucp lp dialout networkmanager scanner docker` |
| Restaurados | blender 5.1.1, obs |

Falta a fase 2 (Windows) e a 3 (GRUB listando os dois).

### Firmware: a BIOS reescreve a BootOrder

A Biostar B550GTA (AMI) **descarta a ordem de boot gravada na NVRAM**.
A cada boot ela varre os discos, recria a entrada genérica `UEFI OS`
apontando para `\EFI\BOOT\BOOTX64.EFI` e a põe no topo.

Comprovado: `efibootmgr -o 0003,0002,0000,0001` gravou, foi confirmado
lendo a NVRAM de volta, e no reboot seguinte a ordem estava
`0002,0000,0001,0003` de novo — bootando a geração antiga pelo
systemd-boot, que ainda ocupava o caminho removível.

Solução na config: `boot.loader.grub.efiInstallAsRemovable = true` +
`efi.canTouchEfiVariables = false`. Em vez de disputar a ordem, o GRUB
passa a *ser* o `\EFI\BOOT\BOOTX64.EFI` que a placa já escolhe sozinha.

#### 🪤 Mudar essa opção exige `--install-bootloader`

Um `nixos-rebuild boot` normal **não** reinstala o GRUB. Ele compara um
estado guardado em `/boot/grub/state` e, se achar que nada relevante
mudou, só regenera o `grub.cfg` — `efiInstallAsRemovable` não entra
nessa comparação. Resultado: a config muda, a geração nova é criada, e
os binários EFI no disco continuam os antigos. O sintoma é traiçoeiro —
**todo rebuild parece não ter efeito**, porque a geração nova nunca é a
que boota.

Como saber qual aconteceu — a diferença na saída do rebuild:

```
updating GRUB 2 menu...                          <- só isto = NÃO instalou
installing the GRUB 2 boot loader into /boot...  <- esta linha = instalou
Installing for x86_64-efi platform.
```

Ao mexer em qualquer coisa de bootloader, force:

```bash
sudo nixos-rebuild boot --install-bootloader
```

E confirme no disco **antes de reiniciar** (o `strings` não está
instalado; `grep -a` trata binário como texto):

```bash
sudo grep -a -m1 -oiE 'grub|systemd-boot' /boot/EFI/BOOT/BOOTX64.EFI
# tem que sair "grub"
```

**Se trocar de placa-mãe**, reverta para `canTouchEfiVariables = true` e
`efiInstallAsRemovable = false` — o comportamento acima é desta placa.

#### Sobras do systemd-boot

`\EFI\SYSTEMD\` e `/boot/loader/` continuam na ESP, com as entradas até
a geração 3. Não atrapalham (nada os invoca), e servem de rede de
segurança: **F11 → "Linux Boot Manager"** ainda boota a geração 3 se o
GRUB quebrar. Só limpe quando tiver certeza de que não vai precisar.

---

## Plano (histórico)

Os **dois** discos foram apagados. Backup no Google Drive.

Ordem das fases:

1. ✅ **NixOS em UEFI** → passos 1–7 abaixo
2. ⬜ **Windows** no outro disco, com o NVMe do NixOS **desconectado**
3. ⬜ **Reconectar** e rodar `nixos-rebuild boot` pro GRUB listar os dois

Instalar o NixOS primeiro é de propósito: o instalador do Windows
reescreve a ordem de boot EFI, então é melhor ele vir depois — e com o
disco do NixOS fora da máquina, onde não tem o que estragar.

---

## Instalação em UEFI — o ponto crítico

O modo de boot é decidido **no pendrive**, não no instalador. Se o
pendrive bootar em CSM/Legacy, o `nixos-generate-config` gera config
legacy e não há o que fazer depois. Foi exatamente o que aconteceu na
instalação anterior.

### 1. BIOS da placa, ANTES de tudo

- `CSM Support` / `Launch CSM` → **Disabled**
- `Boot Mode` → **UEFI** (não "UEFI + Legacy")
- `Secure Boot` → **Disabled** (NixOS só suporta via lanzaboote)
- `SATA Mode` → **AHCI** (nunca RAID/RST — o Windows depois não enxerga o NVMe)

Desligar o CSM é o que garante o modo: sem ele, a placa nem oferece a
opção legacy.

### 2. No menu de boot (F11), escolher a entrada certa

O pendrive aparece **duas vezes**. Escolher a que começa com `UEFI:`

```
UEFI: SanDisk Cruzer      <- ESTA
SanDisk Cruzer            <- legacy, ignorar
```

### 3. Confirmar DENTRO do live USB, antes de particionar

```bash
[ -d /sys/firmware/efi/efivars ] && echo "UEFI ✅" || echo "LEGACY ❌ — reboote"
```

Se der LEGACY, **pare**. Reboote e escolha a entrada `UEFI:`.
Segunda confirmação:

```bash
efibootmgr        # lista entradas EFI -> só funciona em UEFI
```

### 4. Particionar em GPT com ESP

**Confira o nome do disco com `lsblk` no boot atual, imediatamente
antes de particionar.** Os dois NVMe têm 953,9G e a numeração
`nvme0n1`/`nvme1n1` **não é estável entre boots** — nesta máquina os
dois já trocaram de nome de um boot pro outro sem nenhuma mudança de
hardware. Um nome anotado ontem não vale hoje.

```bash
lsblk -o NAME,SIZE,PARTUUID,UUID,FSTYPE,LABEL
```

Identifique o disco pelo conteúdo/UUID, nunca pelo número. Depois
exporte o nome uma vez só e use a variável — assim não tem como errar
no meio da sequência:

```bash
DISK=/dev/nvme0n1        # <- ajuste conforme o lsblk acima

parted $DISK -- mklabel gpt
parted $DISK -- mkpart ESP  fat32 1MB 1GB
parted $DISK -- set 1 esp on
parted $DISK -- mkpart root ext4  1GB 100%

mkfs.fat -F 32 -n BOOT ${DISK}p1
mkfs.ext4 -L nixos     ${DISK}p2
```

`mklabel gpt` é o que zera a tabela MBR antiga. ESP de 1GB é folgada
de propósito: o NixOS guarda um kernel+initrd por geração no /boot, e
512MB enche rápido.

### 5. Montar — a ESP TEM que ir em `/mnt/boot`

```bash
mount /dev/disk/by-label/nixos /mnt
mkdir -p /mnt/boot
mount -o umask=077 /dev/disk/by-label/BOOT /mnt/boot
```

É o erro nº1 de instalação UEFI no NixOS: esquecer de montar a ESP
antes do `nixos-generate-config`. Sem isso o `fileSystems."/boot"` não
entra no `hardware-configuration.nix` e o bootloader não instala.

### 6. Gerar config e conferir que ele detectou UEFI

```bash
nixos-generate-config --root /mnt
grep -A3 'boot.loader' /mnt/etc/nixos/configuration.nix
```

Se aparecer `systemd-boot.enable = true` → **detectou UEFI, certo.**
Se aparecer `grub.device = "/dev/nvme..."` → detectou legacy, algo
saiu errado nos passos 1–3.

```bash
grep -A4 '"/boot"' /mnt/etc/nixos/hardware-configuration.nix   # precisa existir, fsType vfat
```

### 7. Colar esta config e instalar

```bash
curl -L https://raw.githubusercontent.com/KanagawaMarcos/dotenv/main/configuration.nix \
  -o /mnt/etc/nixos/configuration.nix
nixos-install
reboot
```

Depois do boot, a confirmação final:

```bash
[ -d /sys/firmware/efi ] && echo "rodando em UEFI ✅"
efibootmgr -v                       # deve listar a entrada do NixOS
lsblk -o NAME,PTTYPE,FSTYPE,MOUNTPOINT   # /boot vfat montado
nvidia-smi                          # driver proprietário no ar
```

### 8. Ajustes pós-instalação

```bash
passwd kanagawamarcos               # a senha do usuário não vem da config

git config --global user.name  "Marcos Kanagawa"
git config --global user.email "marcos@kanagawa.io"

git clone git@github.com:KanagawaMarcos/dotenv.git ~/Git/dotenv
```

O caminho importa: os comandos de `nixos-rebuild` mais abaixo apontam
para `~/Git/dotenv`. Clonando em outro lugar, ajuste-os junto.

O que **não** é declarativo e precisa ser refeito na mão:

- Senha do usuário (`passwd`)
- Chave SSH do GitHub (`~/.ssh/`)
- Proton-GE via `protonup-ng` (vai pra `~/.steam/root/compatibilitytools.d`)
- Login/biblioteca da Steam, contas do Discord/Telegram/Signal
- Perfis e impressoras do OrcaSlicer/BambuStudio

---

## Como aplicar (em máquina já instalada)

A config é um **flake** e mora neste repo. Não se copia mais nada para
`/etc/nixos` — aponte o `nixos-rebuild` direto para o repo:

```bash
sudo nixos-rebuild test   --flake ~/Git/dotenv#nixos   # aplica só até o próximo reboot
sudo nixos-rebuild switch --flake ~/Git/dotenv#nixos   # confirma
```

`#nixos` é o nome em `nixosConfigurations` no `flake.nix`. O
`/etc/nixos/configuration.nix` que ainda existe na máquina é a cópia
pré-flake, **não é mais usada** — um `nixos-rebuild` sem `--flake` iria
ler aquele arquivo velho e falhar (ele não recebe `inputs`).

⚠️ O `nixos-rebuild` roda via `sudo`, e o flake precisa estar num repo
git: arquivo novo não rastreado pelo git é **invisível** para o flake.
Depois de criar um diretório novo em `overlays/`, faça ao menos
`git add` antes de rebuildar.

**Não copie `hardware-configuration.nix`.** Ele é gerado pelo
`nixos-generate-config` e tem os UUID dos discos. A cópia no repo é só
backup — está sincronizada com a máquina atual (instalação de
2026-09-14, root `aa310bed…`, ESP `4587-D4ED`), mas numa reinstalação
os UUID mudam e o arquivo bom é sempre o gerado na hora.

Para atualizar o backup depois de mexer em disco:

```bash
cp /etc/nixos/hardware-configuration.nix ~/Git/dotenv/hardware-configuration.nix
```

### Dois nixpkgs: o do sistema e o unstable

O `flake.nix` tem **dois** inputs de nixpkgs:

| Input | Aponta para | Quem usa |
|---|---|---|
| `nixpkgs` | uma revisão fixa (26.05) | o sistema inteiro |
| `nixpkgs-unstable` | branch `nixos-unstable` | só o que estiver escrito `unstable.<pacote>` |

O segundo existe para os pacotes que devem ficar sempre na versão mais
nova — hoje só o **gimp** (`unstable.gimp` na lista de pacotes).

⚠️ **"unstable" não quer dizer "atualiza sozinho".** A revisão do branch
fica travada no `flake.lock` igual à outra. Para puxar versão nova:

```bash
cd ~/Git/dotenv
nix flake update nixpkgs-unstable      # só o canal unstable
sudo nixos-rebuild switch --flake ~/Git/dotenv#nixos
```

Um `nix flake update` sem argumento atualiza **os dois** — e aí o sistema
inteiro sai da revisão fixa, que é justamente o download de 12 GiB que a
migração para flake evitou. Use o nome do input.

Cada pacote vindo do unstable arrega a closure dele (as dependências
daquela revisão, não as do sistema), então a conta de disco cresce por
pacote: vale para um punhado deles, não para dezenas.

---

## Dual boot com Windows

O Windows vai no disco que ainda tem o **Ubuntu antigo** (root UUID
`cffb5b77-72ea-…`), com **ESP própria**. O outro é o do NixOS.

**Não confie no nome do device** — ele troca entre boots. Descubra qual
é qual no momento em que for mexer:

```bash
findmnt -no SOURCE /          # ex.: /dev/nvme1n1p2
lsblk -no PKNAME $(findmnt -no SOURCE /)   # -> nome do disco do NIXOS
```

O disco que esse comando devolver é o que **sai da máquina**. O outro é
o que recebe o Windows.

Na hora de abrir o gabinete o nome não ajuda em nada, então anote antes
o **serial** do disco do NixOS e confira na etiqueta:

```bash
lsblk -dno SERIAL,MODEL /dev/$(lsblk -no PKNAME $(findmnt -no SOURCE /))
```

Não compartilhe uma ESP só: o instalador do Windows reescreve a ordem
de boot EFI e às vezes o `\EFI\Boot\bootx64.efi` — que nesta config é
justamente onde mora o GRUB (veja `efiInstallAsRemovable` acima).
Discos separados isolam o estrago.

**Desconecte fisicamente o NVMe do NixOS antes de instalar o Windows.**
O instalador dele escreve o bootloader em qualquer ESP que encontrar;
com o disco fora da máquina, ele é obrigado a criar a própria. É a
única forma de garantir isso — não existe opção no instalador pra
escolher onde vai a ESP.

Depois de instalar, reconecte o disco do NixOS.

É por isso que a config usa **GRUB e não systemd-boot**: o
systemd-boot só lista entradas da ESP que ele gerencia, então não
enxergaria o Windows no outro disco (precisaria de `edk2-uefi-shell`
como intermediário). O GRUB com `useOSProber` acha e faz chainload.

Depois de instalar o Windows, o menu dele vira o padrão. Para o GRUB
voltar a aparecer e listar os dois:

```bash
sudo nixos-rebuild boot     # roda o os-prober e reescreve o menu
sudo efibootmgr -v          # confere/ajusta a ordem de boot
```

Gotchas já tratados na config:

- `time.hardwareClockInLocalTime = true` — Windows grava o RTC em
  horário local, Linux usa UTC. Sem isto o relógio pula 3h a cada troca.
- `boot.supportedFilesystems = [ "ntfs" ]` — monta as partições do Windows.

Gotchas que dependem de você, **no Windows**:

- **Desligar o Fast Startup** (Painel de Controle → Opções de Energia →
  Escolher a função dos botões → Alterar configurações indisponíveis →
  desmarcar "Ligar inicialização rápida"). Com ele ligado o Windows
  hiberna em vez de desligar, o NTFS fica marcado como sujo e o Linux
  só monta read-only.
- **Secure Boot off** — o Win11 exige UEFI + TPM 2.0, mas **não** exige
  Secure Boot ligado.
- **BitLocker**: se ligar, guarde a chave de recuperação. Mexer na
  ordem de boot EFI pode disparar o pedido da chave.

---

## As três coisas que NÃO podem vir da config antiga

1. **Bootloader.** A config antiga misturava `systemd-boot.enable = true`
   com um bloco `grub` de UEFI — configuração contraditória. Aqui é
   GRUB EFI puro, com `device = "nodev"` (em UEFI **nunca** o disco).

2. **`hardware.nvidia.open`.** Era `false`. A partir do driver 580 a
   NVIDIA só suporta o módulo de kernel **aberto** em GPUs Turing e
   mais novas. Esta GPU é Ampere (GA102) e o driver do 26.05 é o 595,
   então tem que ser `true`.

3. **`system.stateVersion`.** Era `25.11`. Esse campo descreve *em que
   versão a máquina foi instalada*, não qual nixpkgs está em uso.
   Na reinstalação será `26.05`.

---

## Fixes preservados da config antiga

- `GTK_ENABLE_PRIMARY_PASTE=false` — mata o colar com botão do meio.
- `power-profiles-daemon` desligado.
- `programs.nix-ld` para rodar binários não-Nix.
- Flakes + `nix-command` habilitados.
- Grupos `uucp` / `dialout` (Arduino, serial, K40).
- Steam + gamescope + gamemode + `STEAM_EXTRA_COMPAT_TOOLS_PATHS`.
- Avahi + SANE + `sane-airscan` (impressora/scanner de rede).
- Fix do OrcaSlicer/BambuStudio — ver [`orca-slicer.txt`](orca-slicer.txt).

## Fixes novos

- **OrcaSlicer/BambuStudio**: `GBM_BACKEND=dri` agora é aplicado só a
  esses dois apps (helper `wrapGL`), em vez de global — global era o
  que derrubava a sessão. Substitui o wrapper manual com nixGL, e
  funciona também pelo menu do desktop, não só pelo terminal.
- **Bluetooth** saiu do `hardware-configuration.nix` (que é sobrescrito
  pelo `nixos-generate-config`) e foi pro `configuration.nix`.
- **Drivers Epson** saíram da lista de pacotes do usuário e foram pra
  `services.printing.drivers` — é lá que o CUPS procura.
- **Docker**: o pacote estava instalado mas o daemon nunca foi ativado.
  Agora `virtualisation.docker.enable = true`.
  ⚠️ O grupo `docker` equivale a root; remova de `extraGroups` se preferir.
- **zram** como swap.

## Removido

- Bloco `services.logind.settings.Login` com
  `IdleAction = "ignore"` / `IdleActionSec = "infinity"`. Redundante: é
  exatamente o padrão do systemd, então o comportamento não muda. Se um
  dia a máquina começar a suspender sozinha, é aqui que volta.
- Pacotes que estavam na config antiga e **não** foram migrados:
  `blender`, `obs-studio`, `unetbootin`, `gimp-with-plugins`,
  `cargo`, `rustfmt`, `stdenv.cc.cc`. Alguns têm substituto na config
  nova (`kdePackages.isoimagewriter` no lugar do unetbootin;
  `cargo`/`rustfmt` vêm do `rustup`). `blender`, `obs-studio` e o
  `gimp` (3.0.8, sem os plugins) já voltaram para
  `users.users.kanagawamarcos.packages`.
- `inkscape-with-extensions` virou `inkscape` puro (sem as extensões).

## Adaptações KDE → Pantheon

- `plasma6` → `pantheon`; `sddm` → `lightdm`.
- `KWIN_DRM_USE_EGL_STREAMS` removido (era específico do KWin).
- ⚠️ **O Pantheon do 26.05 sobe em Wayland, não em X11.** A suposição
  original (X11) estava errada; medido na máquina com
  `loginctl show-session … -p Type` → `Type=wayland`,
  `Desktop=pantheon-wayland`. O `services.xserver.enable` continua
  necessário (LightDM, xkb, Xwayland), mas a sessão é Wayland — e
  funciona bem com o NVIDIA 595 + módulo aberto.
- `NIXOS_OZONE_WL` continua desligado. Não é por ser X11 (não é): é
  porque essa variável quebrava o kdenlive na config antiga. Os apps
  Electron rodam via Xwayland sem problema.
- `kate` e `isoimagewriter` mantidos: são apps Qt e rodam normal no Pantheon.
- `wl-clipboard` adicionado ao lado do `xclip`.
