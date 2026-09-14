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

| Disco | Papel | Layout |
|---|---|---|
| `nvme0n1` | **NixOS** | GPT — `p1` ESP 1G vfat → `/boot` · `p2` ext4 952,9G → `/` |
| `nvme1n1` | **livre, pro Windows** | GPT — ainda com o Ubuntu antigo (ext4 952,8G + ESP 1G) |

> ⚠️ **Os discos saíram invertidos em relação ao plano original.** O
> plano dizia NixOS no `nvme1n1`; na prática ele foi pro `nvme0n1`.
> Isso inverte qual disco você desconecta na fase do Windows — veja
> [Dual boot](#dual-boot-com-windows). Confira sempre com `lsblk`
> antes de mexer: a numeração NVMe não é estável entre boots, o
> vínculo confiável é o UUID no `hardware-configuration.nix`.

Confirmado na máquina:

- `/sys/firmware/efi/efivars` existe → **UEFI de verdade**
- `nixos-version` → `26.05.9592 (Yarara)`, `system.stateVersion = "26.05"`
- ESP tipo *EFI System*, vfat, montada em `/boot` (40M de 1022M usados)
- `fileSystems."/boot"` presente no `hardware-configuration.nix`
  (o erro nº1 de instalação UEFI **não** aconteceu)

Falta a fase 2 (Windows) e a 3 (GRUB listando os dois).

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

**Confira o nome do disco com `lsblk` antes de cada comando.** Os dois
NVMe têm 953,9G e a numeração `nvme0n1`/`nvme1n1` **não é estável entre
boots** — foi exatamente por isso que a instalação real acabou no
`nvme0n1` e não no `nvme1n1` como este passo dizia originalmente.

```bash
lsblk -o NAME,SIZE,PTTYPE,FSTYPE,LABEL
```

Identifique o disco pelo conteúdo, não pelo número. Depois exporte o
nome uma vez só e use a variável — assim não tem como errar no meio:

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

git clone git@github.com:KanagawaMarcos/dotenv.git ~/dotenv
```

O que **não** é declarativo e precisa ser refeito na mão:

- Senha do usuário (`passwd`)
- Chave SSH do GitHub (`~/.ssh/`)
- Proton-GE via `protonup-ng` (vai pra `~/.steam/root/compatibilitytools.d`)
- Login/biblioteca da Steam, contas do Discord/Telegram/Signal
- Perfis e impressoras do OrcaSlicer/BambuStudio

---

## Como aplicar (em máquina já instalada)

```bash
sudo cp configuration.nix /etc/nixos/configuration.nix
sudo nixos-rebuild test     # aplica só até o próximo reboot
sudo nixos-rebuild switch   # confirma
```

**Não copie `hardware-configuration.nix`.** Ele é gerado pelo
`nixos-generate-config` e tem os UUID dos discos. A cópia no repo é só
backup — está sincronizada com a máquina atual (instalação de
2026-09-14, root `aa310bed…`, ESP `4587-D4ED`), mas numa reinstalação
os UUID mudam e o arquivo bom é sempre o gerado na hora.

Para atualizar o backup depois de mexer em disco:

```bash
cp /etc/nixos/hardware-configuration.nix ~/dotenv/hardware-configuration.nix
```

---

## Dual boot com Windows

O Windows vai no **`nvme1n1`** (o disco que ainda tem o Ubuntu antigo),
com **ESP própria**. O NixOS está no `nvme0n1` — **confira com `lsblk`
antes**, a numeração pode trocar entre boots:

```bash
lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT
# o disco cujo p2 está montado em "/" é o do NixOS — esse é o que SAI da máquina
```

Não compartilhe uma ESP só: o instalador do Windows reescreve a ordem
de boot EFI e às vezes o `\EFI\Boot\bootx64.efi`. Discos separados
isolam o estrago.

**Desconecte fisicamente o NVMe do NixOS (`nvme0n1`) antes de instalar
o Windows.**
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
  nova (`kdePackages.isoimagewriter` no lugar do unetbootin; `krita` no
  lugar do gimp; `cargo`/`rustfmt` vêm do `rustup`). Os que não têm —
  `blender` e `obs-studio` — foram perda real; adicione de volta em
  `users.users.kanagawamarcos.packages` se fizer falta.
- `inkscape-with-extensions` virou `inkscape` puro (sem as extensões).

## Adaptações KDE → Pantheon

- `plasma6` → `pantheon`; `sddm` → `lightdm`.
- `KWIN_DRM_USE_EGL_STREAMS` removido (era específico do KWin).
- `NIXOS_OZONE_WL` continua desligado — Pantheon é sessão X11, e era
  justamente essa variável que quebrava o kdenlive.
- `kate` e `isoimagewriter` mantidos: são apps Qt e rodam normal no Pantheon.
- `wl-clipboard` adicionado ao lado do `xclip`.
