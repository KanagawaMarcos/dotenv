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

## Estado atual (2026-11-17): dual boot funcionando ✅

Seções 0–4 já foram executadas. O que vale **hoje**:

| | Disco "NixOS" | Disco "Windows" (ex-`storage`) |
|---|---|---|
| Serial | `C1D307021B0901178259` | `TPBF2007240030400210` |
| Partições | ESP vfat `4587-D4ED` (`/boot`) + ext4 raiz | `Microsoft reserved` 16M + NTFS (sem ESP) |
| Bootloaders na ESP | GRUB em `\EFI\BOOT\BOOTX64.EFI` **e** Windows em `\EFI\Microsoft\Boot\bootmgfw.efi` | — |
| Raiz | ext4 UUID `aa310bed-f9ca-4925-86be-78077712946a` | NTFS UUID `226A1DC16A1D9321` |

- **A ESP do NixOS é compartilhada com o Windows** (o disco do NixOS
  estava visível na instalação). Detalhes e consequências na seção
  *Estado real após a instalação*, no fim. **Não reformate essa ESP sem
  antes salvar o `\EFI\Microsoft\`.**
- O GRUB do NixOS lista o Windows via `useOSProber = true`
  (`configuration.nix`, bloco `boot.loader`).
- `time.hardwareClockInLocalTime = true` já está na config.
- ⬜ **Pendente no Windows:** desligar o Fast Startup e guardar a chave do
  BitLocker (seção 2, passo 4).
- O `/mnt/storage` não existe mais. A partição `Microsoft reserved`
  ainda carrega o UUID ext4 antigo `4a99c463-...`: **nunca monte esse UUID**.

O plano original (refazer do zero) previa **uma ESP por disco**, que é
o ideal. As seções abaixo descrevem esse plano.

> 🚨 Os nomes `nvme0n1` e `nvme1n1` **trocam entre boots**. Sempre
> identifique os discos por serial ou UUID:
> ```bash
> lsblk -o NAME,SIZE,SERIAL,PARTUUID,UUID,FSTYPE,LABEL,MOUNTPOINTS
> lsblk -no PKNAME $(findmnt -no SOURCE /)   # disco do NixOS neste boot
> ```

## 0. Antes de começar

- [ ] **Backup do disco de destino.** O instalador do Windows apaga o
      que estiver nele.
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
3. Instale no único disco visível (serial `TPBF2007240030400210`). Apague
   as partições dele e deixe o instalador criar as dele (ESP, MSR, NTFS,
   recovery). **Se o instalador não criar uma ESP nesse disco, é porque
   ele está enxergando a ESP do outro**: o disco do NixOS não foi
   desativado de verdade (foi o que aconteceu em 2026-11-17).
4. Já no Windows, no primeiro boot (pós-instalação):

   | Item | Necessidade | Status |
   |---|---|---|
   | Fast Startup desligado | **Obrigatório** em dual boot | ⬜ conferir |
   | Chave do BitLocker guardada | **Obrigatório se a criptografia estiver ligada** | ⬜ conferir |
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
     risco é maior que o normal**: o Windows boota via chainload do GRUB
     a partir de uma ESP compartilhada com o NixOS. Atualizar o GRUB,
     mexer na BIOS ou bootar pelo F11 em vez do GRUB pode fazer o Windows
     pedir a **chave de recuperação** de 48 dígitos. Sem ela, os dados do
     Windows ficam inacessíveis.
     - Conferir: Configurações → Privacidade e segurança → *Criptografia
       do dispositivo*, ou `manage-bde -status` no terminal admin.
     - Se estiver ligada: a chave fica em
       <https://account.microsoft.com/devices/recoverykey>. Guarde uma
       cópia fora do PC, por exemplo no gerenciador de senhas. **Não
       versione a chave neste repositório** (política do `AGENTS.md`).
     - Se o pedido da chave virar rotina a cada boot via GRUB, existem
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

## 4. Ajustar a config do NixOS

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

## 5. Recuperação: o GRUB sumiu

Sintoma: a máquina vai direto para o Windows mesmo escolhendo o disco do
NixOS no F11. Na ESP do NixOS o `\EFI\BOOT\BOOTX64.EFI` foi
sobrescrito. Acontece quando o Windows usa a ESP do NixOS, como hoje, e
uma instalação ou uma atualização grande grava o fallback dele ali.

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
   ⚠️ Isso também apaga o bootloader do Windows (`\EFI\Microsoft\`).
   Antes de reformatar, copie essa pasta, se ela ainda existir, e
   devolva-a depois. Se não der, conserte pelo pen drive do Windows
   (Reparar → Prompt): `bcdboot C:\Windows /s <letra-da-ESP>: /f UEFI`.

Rede de segurança extra: as sobras do systemd-boot (`\EFI\SYSTEMD\`,
geração 3) continuam na ESP do NixOS. **F11 → "Linux Boot Manager"**
ainda boota, se não tiverem sido limpas.

## Estado real após a instalação (2026-11-17)

Instalado e funcionando. O GRUB lista NixOS + Windows após `nixos build`
(`Found Windows Boot Manager on /dev/nvme0n1p1@/EFI/Microsoft/Boot/bootmgfw.efi`).

O que saiu diferente do plano:

- **O disco do NixOS estava visível durante a instalação.** Por isso o
  Windows **não criou ESP própria**: gravou o bootloader em
  `\EFI\Microsoft\` da **ESP do NixOS** (`4587-D4ED`). O disco do Windows
  ficou só com `Microsoft reserved` (16M) + NTFS. O `\EFI\BOOT\BOOTX64.EFI`
  (GRUB) **não** foi sobrescrito.
- Consequências:
  - O Windows **só boota com o disco do NixOS presente** (via GRUB, ou
    F11 → "Windows Boot Manager"). Se o disco do NixOS for removido ou a
    ESP reformatada, o Windows precisa de reparo (`bcdboot` a partir da
    mídia do Windows).
  - Grandes atualizações do Windows podem mexer na ESP do NixOS. Se o
    GRUB sumir, siga a seção 5.
  - **Não reformate a ESP do NixOS** sem antes copiar `\EFI\Microsoft\`.
- A partição `Microsoft reserved` de 16M **herdou a assinatura ext4 do
  antigo `storage`** (UUID `4a99c463-...`, label `storage`). O
  `fileSystems."/mnt/storage"` foi removido do `configuration.nix` para
  não montá-la. Não reutilize esse UUID.
- Se for refazer do zero e quiser discos 100% independentes: **desative
  o NVMe do NixOS na BIOS de verdade** (ou desconecte) antes do
  instalador. Confira no instalador do Windows que só um disco aparece.

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
