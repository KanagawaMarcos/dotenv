# Dual boot Windows 11 + NixOS — runbook reproduzível

Roteiro para (re)fazer o dual boot desta máquina a partir do zero, seja
por uma pessoa ou por uma sessão nova do Claude. Escrito em 2026-11-17.
Contexto de firmware, discos e GRUB: veja o [README](../README.md),
seções *Estado atual*, *Firmware: a BIOS reescreve a BootOrder* e
*Dual boot com Windows*.

> **Para o Claude numa sessão nova:** leia este arquivo inteiro e o
> README antes de agir. Os comandos que precisam de root o usuário roda
> com `! pkexec $(command -v <cmd>) ...`, porque `sudo` sem TTY falha.
> Para aplicar a config, use `nixos build` (= `nixos-rebuild switch
> --flake ~/Git/dotenv#nixos`), nunca o `nixos-rebuild` direto.

## Resumo da arquitetura

| | Disco "NixOS" | Disco "Windows" (hoje `storage`) |
|---|---|---|
| Serial | `C1D307021B0901178259` | `TPBF2007240030400210` |
| ESP | própria, UUID `4587-D4ED`, em `/boot` | própria, criada pelo instalador do Windows |
| Bootloader | GRUB em `\EFI\BOOT\BOOTX64.EFI` (`efiInstallAsRemovable`) | Windows Boot Manager |
| Raiz | ext4 UUID `aa310bed-f9ca-4925-86be-78077712946a` | NTFS |

- **Cada disco tem a própria ESP.** Nunca compartilhar.
- O GRUB do NixOS lista o Windows via `useOSProber = true`
  (`configuration.nix`, bloco `boot.loader`).
- `time.hardwareClockInLocalTime = true` já está na config.

> 🚨 Os nomes `nvme0n1` e `nvme1n1` **trocam entre boots**. Sempre
> identifique os discos por serial ou UUID:
> ```bash
> lsblk -o NAME,SIZE,SERIAL,PARTUUID,UUID,FSTYPE,LABEL,MOUNTPOINTS
> lsblk -no PKNAME $(findmnt -no SOURCE /)   # disco do NixOS neste boot
> ```

## 0. Antes de começar

- [ ] **Backup do `/mnt/storage`.** O Windows vai para esse disco e a
      partição ext4 inteira será apagada.
- [ ] Anote o serial do disco do NixOS (tabela acima) para reconhecê-lo
      na BIOS ou na etiqueta.
- [ ] Secure Boot **desligado** (estado atual: `bootctl status` →
      `Secure Boot: disabled`). O Win11 exige UEFI + TPM 2.0, mas não
      exige Secure Boot.

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

1. **Desative o disco do NixOS** na BIOS ou desconecte-o fisicamente
   (confira pelo serial `C1D307021B0901178259`). É o passo mais
   importante: o instalador do Windows grava o bootloader dele em
   qualquer ESP que encontrar, e esta placa sempre boota
   `\EFI\BOOT\BOOTX64.EFI`, que é justamente onde mora o GRUB.
2. Boote pelo pen drive (**F11** = menu de boot da placa) → Ventoy →
   Windows.
3. Instale no único disco visível (o ex-`storage`). Apague as partições
   dele e deixe o instalador criar as dele (ESP, MSR, NTFS, recovery).
4. Já no Windows:
   - **Desligue o Fast Startup** (Opções de Energia → Escolher a função
     dos botões → desmarcar "Ligar inicialização rápida"). Com ele ligado,
     o NTFS fica marcado como sujo e o Linux monta só leitura.
   - **BitLocker / criptografia do dispositivo:** o Win11 24H2+ liga
     sozinho. **Guarde a chave de recuperação** (dá pra salvar no pen
     drive, que tem espaço sobrando). Mudar a ordem de boot pode disparar
     o pedido da chave.
   - Opcional: deixar o Windows com o RTC em UTC
     (`RealTimeIsUniversal=1` no registro) e remover
     `time.hardwareClockInLocalTime` do NixOS. A config atual faz o
     contrário (NixOS em horário local), e as duas formas funcionam.

## 3. Voltar para o NixOS

1. Reative ou reconecte o disco do NixOS.
2. Se a placa bootar direto no Windows: os dois discos agora têm um
   `\EFI\BOOT\BOOTX64.EFI`, e a placa pode escolher o do Windows.
   - **F11** → escolha o NVMe do NixOS.
   - Na BIOS, coloque o NVMe do NixOS em primeiro na **prioridade de
     discos**. Não adianta usar o `efibootmgr -o`, porque esta placa
     reescreve a BootOrder (veja o README).

## 4. Ajustar a config do NixOS

1. **Remova o volume `storage`** do `configuration.nix`: o bloco
   `fileSystems."/mnt/storage"` e o serviço `systemd.services.storage-owner`.
   Como ele tem `nofail`, o sistema boota mesmo sem esse disco, mas a
   config fica mentindo.
2. Atualize o README: o disco "Storage" virou "Windows".
3. Aplique:
   ```bash
   nixos build
   ```
   Isso roda o `os-prober` e reescreve o `grub.cfg`. Não precisa de
   `--install-bootloader`, porque nada no binário do GRUB mudou.
4. Confira:
   ```bash
   grep -i -A3 'windows' /boot/grub/grub.cfg
   # esperado: menuentry 'Windows Boot Manager (on /dev/nvmeXn1p1)' ...
   ```
5. Reinicie: o GRUB deve listar NixOS e Windows. Teste os dois.
6. Commit e push (política do `AGENTS.md`).

### Se o os-prober não achar o Windows

Adicione uma entrada manual, apontando pelo UUID da ESP do Windows
(`lsblk -o NAME,UUID,FSTYPE,PARTTYPENAME`, a partição vfat "EFI System"
do disco do Windows):

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

## 5. Recuperação: o GRUB sumiu

Sintoma: a máquina vai direto para o Windows mesmo escolhendo o disco do
NixOS no F11. Na ESP do NixOS o `\EFI\BOOT\BOOTX64.EFI` foi
sobrescrito. Isso só acontece se o disco do NixOS estava visível durante
a instalação.

1. Boote pelo pen drive → Ventoy → NixOS (live).
2. Monte **pelo UUID** (os nomes de device trocam):
   ```bash
   sudo mount /dev/disk/by-uuid/aa310bed-f9ca-4925-86be-78077712946a /mnt
   sudo mount /dev/disk/by-uuid/4587-D4ED /mnt/boot
   ```
3. Reinstale o bootloader a partir da geração atual:
   ```bash
   sudo nixos-enter --root /mnt -c \
     'NIXOS_INSTALL_BOOTLOADER=1 /nix/var/nix/profiles/system/bin/switch-to-configuration boot'
   ```
   A saída precisa conter `installing the GRUB 2 boot loader into /boot`.
4. Confira antes de reiniciar:
   ```bash
   sudo grep -a -m1 -oiE 'grub|systemd-boot' /mnt/boot/EFI/BOOT/BOOTX64.EFI   # "grub"
   ```
5. Se a ESP do NixOS tiver sido **apagada ou reformatada**, recrie com
   `mkfs.fat -F32 -i 4587D4ED` para manter o UUID que o
   `hardware-configuration.nix` espera. Depois repita os passos 2–4.

Rede de segurança extra: as sobras do systemd-boot (`\EFI\SYSTEMD\`,
geração 3) continuam na ESP do NixOS. **F11 → "Linux Boot Manager"**
ainda boota, se não tiverem sido limpas.

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
