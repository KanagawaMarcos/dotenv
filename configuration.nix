# ============================================================
# NixOS main system configuration
# File: /etc/nixos/configuration.nix
#
# Máquina: nixos (AMD + NVIDIA GA102 / RTX 30xx)
# NixOS 26.05 (Yarara) — Pantheon
#
# Este arquivo define TODO o estado do sistema operacional:
# boot, drivers, desktop, usuários, pacotes, serviços, etc.
#
# Qualquer mudança aqui só tem efeito após:
#   sudo nixos-rebuild switch
# ============================================================

{ config, pkgs, lib, inputs, ... }:

let
  # ==========================================================
  # HELPER: fix de OpenGL para os slicers 3D
  # ==========================================================
  # Histórico: GBM_BACKEND="dri" global fazia o desktop crashar.
  # A anotação antiga dizia "should be passed only to bambu lab
  # and orca slicer" — é exatamente isso que este wrapper faz:
  # aplica a variável SÓ nesses dois apps, sem poluir a sessão.
  #
  # Se algum dia quebrar, basta trocar `wrapGL pkgs.orca-slicer "orca-slicer"`
  # de volta por `orca-slicer` na lista de pacotes.
  wrapGL = pkg: exe: pkgs.symlinkJoin {
    name = "${lib.getName pkg}-glfix";
    paths = [ pkg ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/${exe} \
        --set GBM_BACKEND dri
        # Se ainda der tela branca, descomente também:
        #   --set WEBKIT_DISABLE_COMPOSITING_MODE 1 \
        #   --set __GL_THREADED_OPTIMIZATIONS 0

      # Os .desktop herdados apontam para o store path original,
      # o que burlaria o wrapper ao abrir pelo menu. Reescreve.
      for f in $out/share/applications/*.desktop; do
        [ -e "$f" ] || continue
        real=$(readlink -f "$f")
        rm "$f"
        substitute "$real" "$f" \
          --replace-quiet "${pkg}/bin/${exe}" "$out/bin/${exe}"
      done
    '';
  };

  # ==========================================================
  # HELPER: shell FHS para o toolchain Android
  # ==========================================================
  # O SDK do Android não é FHS-friendly: `aapt2`, `emulator` e os binários de
  # build-tools são ELFs linkados contra /lib64/ld-linux-x86-64.so.2, que não
  # existe no NixOS. É a armadilha nº 1 de Android aqui.
  #
  # O `android-studio` já resolve isso PARA SI MESMO — ele é um buildFHSEnv
  # (confira: bin/android-studio só faz `exec ...-fhs-env ...`). O problema é que
  # `./gradlew` rodado no terminal fica FORA desse env.
  #
  # Este `android-fhs` expõe o mesmo truque como shell: entra, roda
  # gradle/emulator/adb, sai. O SDK continua em ~/Android/Sdk, gerenciado pelo
  # próprio Studio — e não pelo nixpkgs, de propósito: o androidenv desta revisão
  # só tem plataformas até android-37.0 e o voxi-android exige a 37.1
  # (compileSdk 37 + compileSdkMinor 1). Um SDK no /nix/store é somente-leitura e
  # não se autocorrige quando o AGP pede componente novo.
  #
  # O `programs.nix-ld` lá embaixo cobre PARTE disso, mas só com o conjunto
  # default de libs — sem o Qt e o GL que o emulador precisa. Daí o FHS.
  android-fhs = pkgs.buildFHSEnv {
    name = "android-fhs";
    targetPkgs = p: with p; [
      jdk17                               # AGP 9 exige JDK 17+
      android-tools                       # adb/fastboot já patchados pelo Nix
      which git

      # Dependências dos binários que o SDK Manager baixa (aapt2, d8, ...)
      zlib stdenv.cc.cc.lib expat ncurses5

      # Qt + GL do emulador. `-gpu host` fala com o driver NVIDIA do host, que
      # entra via LD_LIBRARY_PATH no `profile` abaixo.
      libglvnd libxkbcommon fontconfig freetype
      libpulseaudio alsa-lib
      xorg.libX11 xorg.libXext xorg.libXrender xorg.libXi
      xorg.libxcb xorg.libXcursor xorg.libXrandr
    ];
    profile = ''
      export ANDROID_HOME="$HOME/Android/Sdk"
      export ANDROID_SDK_ROOT="$ANDROID_HOME"
      export JAVA_HOME="${pkgs.jdk17.home}"
      # O cmdline-tools do SDK vem ANTES: o `sdkmanager` do pacote
      # android-studio-tools é outra versão e aponta para outro sdk root.
      export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$PATH"
      # Driver NVIDIA do host — requisito do `-gpu host`, não otimização.
      export LD_LIBRARY_PATH="/run/opengl-driver/lib:$LD_LIBRARY_PATH"
    '';
  };
in
{
  # ==========================================================
  # IMPORTS
  # ==========================================================
  # Importa a configuração gerada automaticamente com base
  # no hardware detectado (discos, GPU, CPU, etc.)
  imports = [
    ./hardware-configuration.nix
  ];

  # ==========================================================
  # BOOTLOADER  —  UEFI + GRUB (preparado para dual boot Windows)
  # ==========================================================
  # Requer que o NixOS tenha sido instalado em modo UEFI, com uma
  # partição ESP (FAT32, tipo EF00) montada em /boot.
  # Confira com:  [ -d /sys/firmware/efi ] && echo UEFI || echo LEGACY
  #
  # Por que GRUB e não systemd-boot: o systemd-boot só enxerga
  # entradas dentro da ESP que ele mesmo gerencia. Com o Windows num
  # OUTRO disco, com ESP própria, ele NÃO lista o Windows. O GRUB com
  # os-prober acha e faz chainload da ESP do outro disco.
  #
  # POR QUE `efiInstallAsRemovable` (e `canTouchEfiVariables = false`):
  # o firmware AMI desta Biostar B550GTA REESCREVE a BootOrder da NVRAM
  # a cada boot. Ele varre os discos, recria a entrada genérica
  # "UEFI OS" -> \EFI\BOOT\BOOTX64.EFI e a coloca no topo, descartando
  # qualquer ordem gravada com `efibootmgr -o`. Testado: a ordem foi
  # gravada, confirmada na NVRAM, e voltou sozinha no reboot seguinte.
  #
  # Como não dá para vencer a ordem, o GRUB passa a SER o arquivo que
  # a placa insiste em bootar: `efiInstallAsRemovable` instala o GRUB
  # em \EFI\BOOT\BOOTX64.EFI (o caminho removível padrão do UEFI).
  # Isso também sobrescreve a cópia do systemd-boot que estava lá.
  #
  # As duas opções são mutuamente exclusivas por assertion do NixOS:
  # com `efiInstallAsRemovable` o NixOS não mexe mais na NVRAM.
  # Se um dia trocar de placa-mãe, o certo é voltar para
  # `canTouchEfiVariables = true` + `efiInstallAsRemovable = false`.
  boot.loader = {
    efi.canTouchEfiVariables = false;  # A placa ignora a NVRAM; não adianta escrever
    efi.efiSysMountPoint = "/boot";    # Onde a ESP está montada

    grub = {
      enable = true;
      efiSupport = true;
      efiInstallAsRemovable = true;    # GRUB vai para \EFI\BOOT\BOOTX64.EFI
      device = "nodev";                # Em UEFI é SEMPRE "nodev", nunca o disco
      useOSProber = true;              # Detecta o Windows no outro disco
      configurationLimit = 20;         # Não deixa o menu virar uma lista infinita
    };
  };

  # Windows grava o RTC em horário local; o Linux usa UTC. Sem isto o
  # relógio pula 3h cada vez que você troca de SO.
  time.hardwareClockInLocalTime = true;

  # ==========================================================
  # NETWORKING
  # ==========================================================
  networking = {
    hostName = "nixos";                   # Hostname da máquina

    # Gerenciador de rede (Wi-Fi, Ethernet, VPNs, etc.)
    networkmanager.enable = true;

    # Exemplo de proxy (desativado)
    # proxy.default = "http://user:password@proxy:port/";
    # proxy.noProxy = "127.0.0.1,localhost,internal.domain";
  };

  # ==========================================================
  # BLUETOOTH
  # ==========================================================
  # Estava editado à mão dentro do hardware-configuration.nix, que é
  # SOBRESCRITO por `nixos-generate-config`. Movido para cá.
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };

  hardware.enableRedistributableFirmware = true;

  # ==========================================================
  # TIMEZONE & LOCALE
  # ==========================================================
  time.timeZone = "America/Fortaleza";

  # Locale padrão do sistema
  i18n.defaultLocale = "en_US.UTF-8";

  # Locale específico para formatos brasileiros
  i18n.extraLocaleSettings = {
    LC_ADDRESS       = "pt_BR.UTF-8";
    LC_IDENTIFICATION= "pt_BR.UTF-8";
    LC_MEASUREMENT   = "pt_BR.UTF-8";
    LC_MONETARY      = "pt_BR.UTF-8";
    LC_NAME          = "pt_BR.UTF-8";
    LC_NUMERIC       = "pt_BR.UTF-8";
    LC_PAPER         = "pt_BR.UTF-8";
    LC_TELEPHONE     = "pt_BR.UTF-8";
    LC_TIME          = "pt_BR.UTF-8";
  };

  # ==========================================================
  # DISPLAY SERVER & DESKTOP  (KDE Plasma 6  ->  Pantheon)
  # ==========================================================
  services.xserver = {
    enable = true;                        # Ativa X11

    # Layout de teclado no X11
    xkb = {
      layout = "br";
      variant = "";
    };

    # Driver de vídeo proprietário NVIDIA
    videoDrivers = [ "nvidia" ];
  };

  # Pantheon (elementary OS) — substitui o KDE Plasma 6 da config antiga.
  services.desktopManager.pantheon.enable = true;

  # Display Manager. O módulo do Pantheon já ativa o LightDM com o
  # greeter do Pantheon; mantido explícito como o instalador gerou.
  # (O SDDM do KDE foi removido.)
  services.xserver.displayManager.lightdm.enable = true;

  # ATENÇÃO: o Pantheon do 26.05 sobe em WAYLAND, não em X11.
  # Verificado na máquina:
  #   loginctl show-session ... -p Type -p Desktop
  #   -> Type=wayland  Desktop=pantheon-wayland
  # O `services.xserver.enable` acima continua necessário (LightDM,
  # xkb e Xwayland dependem dele), mas a sessão em si é Wayland.
  #
  # Funciona bem com o driver NVIDIA 595 + módulo aberto + modesetting:
  # a GPU está ativa e o gala (compositor do Pantheon) usa a NVIDIA
  # direto — confirmado no `nvidia-smi`. Se um dia precisar mesmo de
  # X11, force com `services.displayManager.defaultSession = "pantheon"`
  # (a sessão Wayland é "pantheon-wayland").

  # Teclado do console (TTY)
  console.keyMap = "br-abnt2";

  # ==========================================================
  # NVIDIA GPU  —  ATENÇÃO: `open` MUDOU DE false PARA true
  # ==========================================================
  # A GPU desta máquina é uma GA102 (Ampere, RTX 30xx) e o driver
  # do NixOS 26.05 é o 595.x.
  #
  # A partir do ramo 580, a NVIDIA parou de dar suporte ao módulo
  # de kernel PROPRIETÁRIO em GPUs Turing e mais novas — só o módulo
  # aberto funciona. Manter `open = false` (como na config antiga,
  # que rodava em driver mais velho) deixaria a GPU sem módulo.
  #
  # Se um dia voltar para uma GPU Pascal/Maxwell, volte a false.
  hardware.nvidia = {
    package = config.boot.kernelPackages.nvidiaPackages.stable;
    open = true;                          # Módulo de kernel aberto (obrigatório em Ampere+ no 580+)
    modesetting.enable = true;            # Necessário para KMS / sessões modernas
    nvidiaSettings = true;                # Painel nvidia-settings
    powerManagement.enable = false;
  };

  hardware.graphics = {
    enable = true;
    enable32Bit = true;                   # Necessário para Steam/Proton/Wine
  };

  # ==========================================================
  # AUDIO (PipeWire)
  # ==========================================================
  services.pulseaudio.enable = false;     # Desativa PulseAudio antigo
  security.rtkit.enable = true;           # Prioridade realtime para áudio

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    # jack.enable = true;                 # Descomentar se usar JACK
  };

  # ==========================================================
  # POWER MANAGEMENT & LID BEHAVIOR
  # ==========================================================
  services.power-profiles-daemon.enable = false;

  # NOTA: a config antiga tinha um bloco services.logind.settings.Login
  # com HandleLidSwitch = "ignore". Esta máquina é um DESKTOP
  # (chassis_type = 3, Biostar B550GTA) — não tem tampa. Era config
  # morta, foi removida. Se um dia isto virar notebook, era:
  #
  # services.logind.settings.Login = {
  #   HandleLidSwitch = "ignore";
  #   HandleLidSwitchExternalPower = "ignore";
  #   HandleLidSwitchDocked = "ignore";
  # };

  # ==========================================================
  # DUAL BOOT: acesso ao disco do Windows
  # ==========================================================
  # Permite montar as partições NTFS do Windows (leitura e escrita).
  # LEMBRE de desligar o "Fast Startup" no Windows — com ele ligado o
  # NTFS fica marcado como sujo/hibernado e só monta como read-only.
  boot.supportedFilesystems = [ "ntfs" ];

  # ==========================================================
  # SWAP  (NOVO)
  # ==========================================================
  # A instalação antiga tinha partição de swap; esta NÃO tem
  # (swapDevices = [ ] no hardware-configuration.nix). Compilar
  # no Nix, rodar Android Studio/Rider ou fatiar STL grande sem
  # nenhuma swap é convite a OOM. zram resolve sem reparticionar.
  # Para remover: apague as 2 linhas abaixo.
  zramSwap.enable = true;
  zramSwap.memoryPercent = 50;

  # ==========================================================
  # PRINTING, SCANNING & NETWORK DISCOVERY
  # ==========================================================
  services.printing = {
    enable = true;                        # CUPS

    # CORREÇÃO: os drivers Epson estavam na lista de pacotes do
    # usuário, onde o CUPS NÃO os enxerga. Driver de impressora
    # precisa estar aqui para o daemon achar o PPD/filtro.
    drivers = with pkgs; [
      epson_201207w
      epson-escpr
      epson-escpr2
    ];
  };

  services.avahi = {
    enable = true;                        # mDNS / zeroconf (descoberta de impressora e scanner na rede)
    nssmdns4 = true;
    openFirewall = true;
  };

  hardware.sane = {
    enable = true;                        # Scanner
    extraBackends = [ pkgs.sane-airscan ];
  };

  # ==========================================================
  # VIRTUALIZAÇÃO  (NOVO)
  # ==========================================================
  # O pacote `docker` estava na lista do usuário, mas o daemon nunca
  # foi ativado — ou seja, o CLI existia e não funcionava. Ativado.
  #
  # NOTA DE SEGURANÇA: estar no grupo "docker" equivale a root.
  # Se preferir evitar, remova "docker" de extraGroups e use sudo.
  virtualisation.docker.enable = true;

  # ==========================================================
  # ANDROID — adb em aparelho físico
  # ==========================================================
  # NÃO use `programs.adb.enable` aqui: nesta revisão do nixpkgs a opção foi
  # removida e vira erro de assertion na avaliação —
  #   "no longer has any effect; systemd 258 handles uaccess rules automatically"
  # O systemd 258 já aplica a regra de uaccess para dispositivo Android, então a
  # regra udev da Google e o grupo `adbusers` deixaram de ser necessários.
  #
  # O que sobra é garantir o binário: `android-tools` entra na lista de pacotes
  # (ver seção Android abaixo), porque o `android-studio-tools` entrega
  # sdkmanager/avdmanager/apkanalyzer e NÃO entrega `adb`.

  # ==========================================================
  # NIX & COMPATIBILITY
  # ==========================================================
  programs.nix-ld.enable = true;          # Executar binários não-Nix

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # Amarra os comandos avulsos (nix-shell -p, nix run nixpkgs#..., <nixpkgs>)
  # à MESMA revisão de nixpkgs que o sistema usa, travada no flake.lock.
  # Sem isto, existem duas fontes que atualizam por comandos diferentes e
  # acabam divergindo sem aviso.
  nix.registry.nixpkgs.flake = inputs.nixpkgs;
  nix.nixPath = [ "nixpkgs=${inputs.nixpkgs}" ];

  # Limpeza automática do store (opcional — descomente se quiser)
  # nix.gc = {
  #   automatic = true;
  #   dates = "weekly";
  #   options = "--delete-older-than 30d";
  # };

  nixpkgs.config.allowUnfree = true;      # Permite software proprietário

  # Pacotes ainda não disponíveis no nixpkgs.
  # rayforge: enquanto o PR NixOS/nixpkgs#565514 não é mergeado.
  # uvtools: enquanto o PR NixOS/nixpkgs#565611 não é mergeado.
  # Vivem dentro deste repo, então a config continua autossuficiente.
  nixpkgs.overlays = [
    (import ./overlays/rayforge)
    (import ./overlays/uvtools)

    # Expõe o canal unstable como `pkgs.unstable.*`, para pacotes avulsos que
    # devem ficar na última versão (ver input nixpkgs-unstable no flake.nix).
    # É um segundo conjunto de pacotes, com closure própria: cada pacote que
    # vier daqui traz as dependências dele, então use com parcimônia.
    (final: _prev: {
      unstable = import inputs.nixpkgs-unstable {
        inherit (final.stdenv.hostPlatform) system;
        config.allowUnfree = true;
      };
    })
  ];

  # ==========================================================
  # USER ACCOUNT
  # ==========================================================
  users.users.kanagawamarcos = {
    isNormalUser = true;
    description = "Marcos Kanagawa";

    extraGroups = [
      "networkmanager"                   # Controle de rede
      "wheel"                            # sudo
      "uucp" "dialout"                   # Serial / Arduino / K40
      "scanner" "lp"                     # Scanner e impressora
      "docker"                           # ATENÇÃO: equivale a root
      # Sem "adbusers": o grupo só existia via `programs.adb.enable`, removido
      # nesta revisão do nixpkgs (systemd 258 cuida do uaccess). Declará-lo aqui
      # falharia na ativação, porque o grupo não é criado por ninguém.
      "kvm"                              # Emulador Android. Hoje /dev/kvm já é 0666
                                         # e funciona sem isto; o grupo é garantia
                                         # se a regra udev mudar.
    ];

    packages = with pkgs; [
      # === System / Dev ===
      git git-lfs wget openssl zlib libgcc
      docker nodejs python3
      dotnetCorePackages.sdk_9_0-bin
      rustc rustup
      emacs vim vscode jetbrains.rider
      chromium google-chrome
      claude-code
      codex
      tmux
      pciutils
      mesa-demos
      alsa-utils
      gh

      # === Android / Embedded ===
      # Studio do canal unstable, NÃO o do pinned. Motivo concreto: o
      # voxi-android pina AGP 9.1.1, e o comentário no libs.versions.toml dele diz
      # que 9.1.1 é "o que o Android Studio 2026.1 abre sem reclamar". O pinned
      # traz 2025.3.4 Patch 1, que recusa o sync por versão de AGP não suportada.
      # O unstable traz 2026.1. Mesmo padrão do `unstable.gimp` abaixo.
      # (O build por CLI funciona nas duas; isto é só a GUI.)
      unstable.android-studio
      android-studio-tools

      # AGP 9 roda em JDK 17+ e o projeto compila para bytecode 17
      # (sourceCompatibility/jvmTarget = 17). A JBR que vem dentro do Studio é uma
      # 21 e existe só DENTRO do FHS env dele — não serve para `./gradlew` no
      # terminal, onde hoje `java` nem resolve. Daí o JDK explícito.
      #
      # NÃO adicione `gradle`: o projeto usa o wrapper, que baixa o 9.3.1. O
      # pkgs.gradle desta revisão é 8.14.4 e seria a versão errada.
      jdk17

      # adb e fastboot. O android-studio-tools NÃO os inclui, e `programs.adb`
      # não existe mais nesta revisão — o systemd 258 já resolve a permissão do
      # dispositivo, então basta ter o binário no PATH.
      android-tools

      android-fhs                        # ver helper no topo do arquivo
      arduino-ide

      # === Design / CAD / Maker ===
      freecad kicad easyeda2kicad
      code-cursor
      mkcert pnpm vlc
      ffmpeg-full
      prusa-slicer
      rayforge
      uvtools

      # === Media ===
      lmms
      blender                            # 3D; usa a GPU NVIDIA (CUDA/OptiX)
      obs-studio                         # Captura/streaming

      # === Communication ===
      thunderbird discord telegram-desktop signal-desktop
      localsend

      # === Gaming ===
      mangohud protonup-ng lutris heroic bottles godot

      # === Utilities ===
      xclip
      wl-clipboard                       # Pantheon/GTK: complemento ao xclip
      mission-center
      transmission_4
      bruno
      libreoffice
      scribus

      # === Editor / Utils que vieram do KDE ===
      # Continuam funcionando no Pantheon (são só apps Qt).
      kdePackages.kate
      kdePackages.isoimagewriter

      # === Impressão 3D / Laser ===
      meerk40t
      (wrapGL orca-slicer  "orca-slicer")   # ver helper `wrapGL` no topo
      (wrapGL bambu-studio "bambu-studio")  # ver helper `wrapGL` no topo

      # === Outros ===
      ollama
      peazip
      krita
      inkscape
      unstable.gimp                      # do canal unstable, sempre o mais novo
    ];
  };

  # ==========================================================
  # GAMING SYSTEM
  # ==========================================================
  programs.steam = {
    enable = true;
    gamescopeSession.enable = true;       # Sessão gamescope no LightDM
  };

  programs.gamemode.enable = true;

  # ==========================================================
  # BROWSERS
  # ==========================================================
  programs.firefox.enable = true;

  # ==========================================================
  # SYSTEM PACKAGES
  # ==========================================================
  environment.systemPackages = with pkgs; [
    vim
    wget
    git
  ];

  # ==========================================================
  # ENVIRONMENT VARIABLES
  # ==========================================================
  environment.variables = {
    # Desativa o colar com botão do meio. No Pantheon (GTK) isso
    # pesa ainda mais do que pesava no KDE.
    GTK_ENABLE_PRIMARY_PASTE = "false";

    # GBM_BACKEND="dri" NÃO vai aqui — como global ele derrubava o
    # desktop. Agora é aplicado só ao orca-slicer/bambu-studio pelo
    # helper `wrapGL` lá em cima.
  };

  environment.sessionVariables = {
    STEAM_EXTRA_COMPAT_TOOLS_PATHS =
      "\${HOME}/.steam/root/compatibilitytools.d";

    # Onde o Android Studio instala o SDK. Precisa estar no ambiente para o
    # Gradle achar a plataforma android-37.1 sem `local.properties` — que é
    # por-máquina e está no .gitignore do voxi-android.
    ANDROID_HOME     = "\${HOME}/Android/Sdk";
    ANDROID_SDK_ROOT = "\${HOME}/Android/Sdk";

    # Notas da config antiga, mantidas por contexto:
    # NIXOS_OZONE_WL = "1";
    #   -> faz apps Electron/Chromium rodarem em Wayland nativo. A
    #      sessão AQUI É WAYLAND (ver nota no bloco do Pantheon), então
    #      ligar isto é tecnicamente possível — mas segue desativado de
    #      propósito: era justamente esta variável que quebrava o
    #      kdenlive na config antiga. Os apps Electron rodam via
    #      Xwayland, que funciona. Só mexa se tiver um motivo.
    # KWIN_DRM_USE_EGL_STREAMS = "0";
    #   -> era específico do KWin/KDE. Não existe mais razão no Pantheon.
  };

  # ==========================================================
  # SYSTEM VERSION (NUNCA ALTERAR LEVEMENTE)
  # ==========================================================
  # 26.05 = versão em que ESTA máquina foi instalada.
  # A config antiga tinha 25.11; copiar aquele valor para cá estaria
  # ERRADO — este campo descreve a instalação, não o nixpkgs.
  system.stateVersion = "26.05";
}
