# ============================================================
# NixOS main system configuration
# Fonte canônica: ~/Git/dotenv/configuration.nix
#
# Máquina: nixos (AMD + NVIDIA GA102 / RTX 30xx)
# NixOS 26.05 (Yarara) — Pantheon
#
# Este arquivo define TODO o estado do sistema operacional:
# boot, drivers, desktop, usuários, pacotes, serviços, etc.
#
# Qualquer mudança aqui só tem efeito após:
#   nixos build
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

      # O resto do que o emulador 37.x pede e não traz em emulator/lib64.
      # Levantado com `ldd` sobre emulator, qemu-system-x86_64 e as libs/
      # plugins Qt dele, dentro deste FHS. Sem libpng o qemu nem carrega.
      libpng libbsd dbus libdrm libuuid nss nspr
      xorg.libICE xorg.libSM xorg.libxkbfile
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

  # ==========================================================
  # HELPER: chrome-headless-shell para o HyperFrames
  # ==========================================================
  # O HyperFrames (render de vídeo a partir de HTML) captura frames por
  # `HeadlessExperimental.beginFrame`, que NÃO existe no Chrome/Chromium
  # normal — só no binário `chrome-headless-shell`. Sem ele a CLI cai no
  # modo screenshot, que funciona mas levou ~1,8x o tempo num teste de
  # 300 frames (10,7s contra 5,9s).
  #
  # A CLI se oferece para baixar esse binário sozinha, em
  # ~/.cache/hyperframes/chrome. Esse download NÃO roda aqui: é um ELF
  # linkado contra libglib/libnss/libX11 de distro. Mesma armadilha do SDK
  # do Android acima. O nix-ld cobriria em teoria, mas seria preciso
  # listar ~20 libs à mão e versionar o download por fora do Nix.
  #
  # O nixpkgs já empacota exatamente esse binário, com autoPatchelf, dentro
  # do playwright-driver. Os overrides desligam chromium, firefox, webkit e
  # ffmpeg — sobra só o headless shell (99 MiB em vez de ~1 GiB).
  #
  # O `runCommand` existe por um motivo só: o linkFarm nomeia o diretório
  # como `chromium_headless_shell-<revisão>`, e a revisão muda a cada bump
  # do playwright. O glob resolve isso no build, então o caminho fixo
  # exportado em HYPERFRAMES_BROWSER_PATH não quebra no update.
  #
  # Nota: o headless shell renderiza por swiftshader (GPU em software).
  # Para composição com WebGL/Three.js pesado, o Chrome do sistema usa a
  # NVIDIA e pode ser mais rápido — nesse caso rode o render com
  # HYPERFRAMES_BROWSER_PATH=$(command -v google-chrome) na frente.
  hyperframes-headless-shell =
    let
      browsers = pkgs.playwright-driver.browsers.override {
        withChromium = false;
        withFirefox = false;
        withWebkit = false;
        withFfmpeg = false;
        withChromiumHeadlessShell = true;
      };
    in
    pkgs.runCommand "hyperframes-headless-shell" { } ''
      shell=$(echo ${browsers}/chromium_headless_shell-*/chrome-headless-shell-linux64/chrome-headless-shell)
      test -x "$shell"
      mkdir -p $out/bin
      ln -s "$shell" $out/bin/chrome-headless-shell
    '';

  # O AppImage permanece em ~/Applications (é o binário baixado), mas seu
  # lançador e entrada de menu são declarados nesta configuração.
  openmausbot = pkgs.writeShellScriptBin "openmausbot" ''
    exec ${pkgs.appimage-run}/bin/appimage-run \
      "$HOME/Applications/OpenMausBot-0.1.115-x86_64.AppImage" "$@"
  '';

  openmausbot-desktop = pkgs.makeDesktopItem {
    name = "openmausbot";
    desktopName = "OpenMausBot";
    comment = "Open-source local AI bot workspace";
    exec = "${openmausbot}/bin/openmausbot";
    icon = "applications-internet";
    categories = [ "Development" "Utility" ];
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
  # STORAGE — NVMe de dados separado
  # ==========================================================
  fileSystems."/mnt/storage" = {
    device = "/dev/disk/by-uuid/4a99c463-1a6c-43d1-a92e-16c15ec3a7f0";
    fsType = "ext4";
    options = [ "defaults" "nofail" ];
  };

  # A raiz do ext4 nasce como root. Mantém o ponto de montagem utilizável
  # pelo usuário local após cada boot, sem dar permissões especiais ao disco.
  systemd.services.storage-owner = {
    description = "Define o dono do volume /mnt/storage";
    wantedBy = [ "multi-user.target" ];
    after = [ "local-fs.target" ];
    unitConfig.RequiresMountsFor = [ "/mnt/storage" ];
    serviceConfig.Type = "oneshot";
    script = ''
      ${pkgs.coreutils}/bin/chown kanagawamarcos:users /mnt/storage
    '';
  };

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
      variant = "abnt2";                  # explícito; ver nota do Xwayland abaixo
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

  # Entra direto na sessão Pantheon ao iniciar o computador.
  # A senha continua necessária para sudo e para desbloquear a tela.
  services.displayManager.autoLogin = {
    enable = true;
    user = "kanagawamarcos";
  };

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

  # Xwayland NÃO herda o layout do compositor nesta sessão Pantheon.
  # Medido na máquina: `gsettings get org.gnome.desktop.input-sources sources`
  # devolve [('xkb','br')] e os apps Wayland nativos ficam certos, mas
  # `setxkbmap -query` no Xwayland devolvia `layout: us`.
  #
  # Efeito prático: todo app que roda via Xwayland (o Chrome, por exemplo, que
  # sobe em X11 por padrão) ficava sem cedilha e sem as dead keys de ~ ´ ^ —
  # era o motivo de não dar pra acentuar no navegador.
  #
  # Esta unit reaplica o layout no Xwayland quando a sessão sobe. Só afeta o
  # Xwayland; os apps Wayland nativos já estavam corretos.
  systemd.user.services.xwayland-keymap = {
    description = "Aplica o layout br-abnt2 no Xwayland";
    after = [ "graphical-session.target" ];
    wantedBy = [ "graphical-session.target" ];
    serviceConfig = {
      Type = "oneshot";
      Environment = "DISPLAY=:0";
      # O Xwayland pode demorar a aceitar conexão; tenta algumas vezes.
      ExecStart = "${pkgs.bash}/bin/bash -c '"
        + "for i in 1 2 3 4 5 6 7 8 9 10; do "
        + "${pkgs.setxkbmap}/bin/setxkbmap -layout br -variant abnt2 && exit 0; "
        + "sleep 2; done; exit 1'";
      RemainAfterExit = true;
    };
  };

  # Pastas especiais do XDG para usuários novos. Sem isto o
  # xdg-user-dirs não gera ~/.config/user-dirs.dirs, `xdg-user-dir PICTURES`
  # cai para $HOME, e os screenshots do Pantheon vão parar soltos na home.
  environment.etc."xdg/user-dirs.defaults".text = ''
    DESKTOP=Desktop
    DOWNLOAD=Downloads
    DOCUMENTS=Documents
    PICTURES=Pictures
    VIDEOS=Videos
    MUSIC=Music
    TEMPLATES=Templates
    PUBLICSHARE=Public
  '';

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

  # Põe ~/.local/bin no PATH. Necessário porque o prefixo global do npm
  # aponta para ~/.local (ver ~/.npmrc): o default dele é o store path do
  # nodejs, que é somente-leitura, então `npm i -g` falhava. É por aí que
  # entra a CLI do hyperframes, que não tem pacote no nixpkgs e sobe de
  # versão quase diariamente — por isso fica no npm e não aqui.
  environment.localBinInPath = true;

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
  # kytyps5: emulador de PS5, compilado do fonte (não existe no nixpkgs).
  # Vivem dentro deste repo, então a config continua autossuficiente.
  nixpkgs.overlays = [
    (import ./overlays/rayforge)
    (import ./overlays/uvtools)
    (import ./overlays/kytyps5)

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
      git git-lfs wget openssl age zlib libgcc
      unzip                              # `hyperframes doctor` cobra um extrator
                                         # de archive; era a única dependência
                                         # faltando na máquina.
      docker nodejs python3
      dotnetCorePackages.sdk_9_0-bin
      rustc rustup
      emacs vim vscode jetbrains.rider
      chromium google-chrome

      # claude-code NÃO entra aqui — vem do npm, em ~/.local/bin.
      #
      # Não é preferência: a CLI do Claude Code trava o acesso a modelo por
      # versão dela mesma. Pedir o Opus 5.5 na 2.1.223 (a desta revisão do
      # nixpkgs, publicada em 2026-08-05) devolve erro do servidor, não um
      # fallback silencioso:
      #
      #   400 Claude Code 2.1.223 does not support this model;
      #       version 2.1.280 or newer is required.
      #
      # O Opus 5.5 saiu em 2026-09-22. O nixpkgs pinado parou na 2.1.223 e o
      # nixos-unstable que o flake.lock trava estava na 2.1.278 — duas versões
      # abaixo do mínimo. Perseguir isso pelo lock significaria atualizar o
      # input unstable a cada lançamento de modelo da Anthropic, arrastando
      # junto android-studio, gimp e openlogi.
      #
      # Com o `environment.localBinInPath` acima, /etc/set-environment emite
      # `export PATH="$HOME/.local/bin:$PATH"` — o npm vem na frente. Atualizar
      # é `npm i -g @anthropic-ai/claude-code`, e o auto-update da própria CLI
      # volta a funcionar, porque ~/.local é gravável e o /nix/store não é.
      #
      # O binário é um ELF de distro; quem o faz rodar aqui é o `programs.nix-ld`
      # já ligado mais acima.
      #
      # gemini-cli também vem do npm (`npm i -g @google/gemini-cli`), pelo
      # mesmo motivo de ritmo: em 2026-10-13 o upstream estava na 0.63.0, o
      # pinned na 0.42.0 e o unstable do lock na 0.47.0.
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

      # Backend de captura do HyperFrames — ver helper no topo do arquivo.
      # Precisa estar NESTA lista, não só na sessionVariable: é o que torna o
      # store path uma raiz de GC. Sem isso, o primeiro `nix-collect-garbage`
      # apaga o binário e todo render passa a falhar.
      hyperframes-headless-shell

      # Transcrição do HyperFrames (legenda a partir de áudio/vídeo). A CLI
      # procura `whisper-cli` no PATH, que é justamente o que este pacote
      # entrega. A doc dele manda compilar do fonte com cmake; não precisa.
      # Build de CPU de propósito: a variante CUDA compila o mundo e 24
      # núcleos dão conta. Os modelos .bin ficam fora do Nix, baixados sob
      # demanda para ~/.cache.
      whisper-cpp

      # === Communication ===
      thunderbird discord telegram-desktop signal-desktop
      remmina                            # Cliente RDP para acessar o Windows na rede local
      trayscale                          # GUI do Tailscale (GTK4); ícone no tray via namarupa
      rustdesk                            # Acesso remoto pelo iPhone, fora do caminho do Steam Link

      # === Gaming ===
      mangohud protonup-ng lutris heroic bottles godot
      pcsx2                              # Emulador de PS2 (precisa da BIOS do console)
      kytyps5                            # Emulador de PS5 (overlays/kytyps5)

      # Companion dos periféricos Logitech (HID++). NÃO existe na revisão
      # pinada do `nixpkgs` — entrou depois, então só o canal unstable tem.
      # Por isso o prefixo; sem ele o rebuild falha com "undefined variable".
      unstable.openlogi

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
      # ollama: vem do services.ollama abaixo (servidor + CLI, com CUDA)
      unstable.lmstudio                  # do unstable: o runtime de LLM evolui
                                         # rápido e o pinado ficou na 0.4.15
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
  # TAILSCALE
  # ==========================================================
  # Rede privada entre as máquinas do Marcos. Uso principal: SSH até o
  # MacBook para compilar, testar e subir o voxi-ios (Xcode só roda em macOS).
  # Preferido a ngrok/porta aberta: nada fica exposto na internet pública.
  # Primeiro uso: `sudo tailscale up` e logar na mesma conta do Mac.
  # `openFirewall` libera só a UDP 41641 (conexão direta P2P); sem ela o
  # tráfego cai no relay DERP, que funciona mas é mais lento.
  services.tailscale = {
    enable = true;
    openFirewall = true;
    # Deixa o usuário controlar o tailscaled sem sudo — é o que permite ao
    # Trayscale (GUI) conectar, trocar de conta e ver os peers.
    extraSetFlags = [ "--operator=kanagawamarcos" ];
  };

  # Não sobe no boot: liga na mão com `sudo systemctl start tailscaled`
  # quando precisar. Os dois units precisam sair do multi-user.target —
  # o tailscaled-set tem `Wants=tailscaled.service` e o puxaria de volta.
  systemd.services.tailscaled.wantedBy = lib.mkForce [ ];
  systemd.services.tailscaled-set.wantedBy = lib.mkForce [ ];

  # Tray do wingpanel para apps com StatusNotifierItem (Trayscale, Discord…).
  # O wingpanel do Pantheon 8 não mostra esses ícones sozinho; o antigo
  # `wingpanel-indicator-ayatana` foi removido do nixpkgs (não funciona do
  # Pantheon 8 em diante) e o próprio aviso de remoção aponta este aqui.
  services.desktopManager.pantheon.extraWingpanelIndicators = [
    pkgs.wingpanel-indicator-namarupa
  ];

  # ==========================================================
  # LLM LOCAL
  # ==========================================================
  # O pacote `ollama` sozinho só entrega o CLI: sem `ollama serve` rodando,
  # todo comando falha ao conectar. O serviço sobe o servidor em
  # 127.0.0.1:11434 e já põe o CLI no PATH. A variante CUDA usa a NVIDIA;
  # o `ollama` puro roda só em CPU. Os modelos ficam em /var/lib/ollama.
  services.ollama = {
    enable = true;
    package = pkgs.ollama-cuda;
  };

  # ==========================================================
  # PERIFÉRICOS
  # ==========================================================
  # O openlogi não funciona só com o binário no PATH: ele fala com o mouse
  # Logitech via /dev/hidraw* e /dev/uinput, que nascem root-only. O pacote já
  # traz a regra de udev pronta (lib/udev/rules.d/70-openlogi.rules, com
  # TAG+="uaccess", sem precisar de grupo), mas `environment.systemPackages` e
  # `users.users.*.packages` NÃO ativam regra de udev — só esta opção ativa.
  #
  # Sem isto o app abre e simplesmente não acha o dispositivo.
  services.udev.packages = [ pkgs.unstable.openlogi ];

  # O agente em background, que é quem aplica DPI/botões/bateria.
  #
  # A unit é escrita à mão aqui de propósito. O pacote traz a dele, mas em
  # share/systemd/user/, e o `systemd.packages` do NixOS só varre
  # etc/systemd/user e lib/systemd/user (nixos/lib/systemd-lib.nix) — o
  # caminho do openlogi não é visto, e o resultado é uma unit VAZIA, sem
  # ExecStart, que falha ao iniciar. Isto aqui é uma cópia do upstream.
  systemd.user.services.openlogi-agent = {
    description = "OpenLogi background agent (Logitech HID++ device control)";
    after = [ "graphical-session.target" ];
    wantedBy = [ "graphical-session.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.unstable.openlogi}/bin/openlogi-agent";
      Restart = "on-failure";
      RestartSec = 5;
    };
  };

  # Acesso remoto pelo iPhone. O processo roda dentro da sessão Wayland já
  # autenticada — evita o serviço global do RustDesk, que não recebe o portal
  # de screencast do Wayland. Não cria VPN nem altera a rota do Steam Link.
  systemd.user.services.rustdesk = {
    description = "RustDesk remote desktop host";
    after = [ "graphical-session.target" ];
    wantedBy = [ "graphical-session.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.rustdesk}/bin/rustdesk --server";
      Restart = "on-failure";
      RestartSec = 5;
    };
  };

  # ==========================================================
  # BROWSERS
  # ==========================================================
  programs.firefox.enable = true;

  # LocalSend (alternativa ao AirDrop com o iPhone). Pelo módulo, e não
  # como pacote solto, porque ele abre a porta 53317 TCP/UDP no firewall;
  # sem isso o iPhone não acha o PC.
  programs.localsend.enable = true;

  # ==========================================================
  # SYSTEM PACKAGES
  # ==========================================================
  environment.systemPackages = with pkgs; [
    # Interface reproduzível para a configuração canônica deste repositório.
    (writeShellScriptBin "nixos" ''
      case "$1" in
        build)
          if [ "$#" -eq 1 ]; then
            exec /run/wrappers/bin/sudo ${config.system.build.nixos-rebuild}/bin/nixos-rebuild \
              switch --flake /home/kanagawamarcos/Git/dotenv#nixos
          fi
          ;;
        clean)
          shift
          exec /run/wrappers/bin/sudo ${pkgs.nix}/bin/nix-collect-garbage -d "$@"
          ;;
      esac

      echo "Uso: nixos {build|clean [opções do nix-collect-garbage]}" >&2
      exit 64
    '')

    # No escopo do sistema, para que a regra Polkit do GParted também seja
    # instalada; assim ele abre normalmente pelo menu no Pantheon/Wayland.
    gparted
    openmausbot
    openmausbot-desktop
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

    # Backend de captura do HyperFrames. Sem isto a CLI tenta baixar o
    # próprio chrome-headless-shell, que não roda no NixOS (ELF de distro),
    # e então cai no modo screenshot do Chrome do sistema. Ver o helper
    # `hyperframes-headless-shell` no topo do arquivo.
    HYPERFRAMES_BROWSER_PATH =
      "${hyperframes-headless-shell}/bin/chrome-headless-shell";

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
