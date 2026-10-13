{
  lib,
  stdenv,
  fetchFromGitHub,
  fetchzip,
  cmake,
  ninja,
  llvmPackages,
  pkg-config,
  python3,
  glslang,
  makeWrapper,
  copyDesktopItems,
  makeDesktopItem,
  qt6,
  vulkan-loader,
  alsa-lib,
  libpulseaudio,
  dbus,
  udev,
  wayland,
  wayland-protocols,
  wayland-scanner,
  libdecor,
  libxkbcommon,
  libGL,
  libx11,
  libxcursor,
  libxext,
  libxfixes,
  libxi,
  libxrandr,
  libxscrnsaver,
  libxtst,
}:

let
  # Dependências que o 3rdparty/CMakeLists.txt baixa com FetchContent no
  # configure. O sandbox não tem rede, então vêm fixadas aqui, nas mesmas
  # revisões dos GIT_TAG do upstream, e entram por FETCHCONTENT_SOURCE_DIR_*.
  opus = fetchFromGitHub {
    owner = "xiph";
    repo = "opus";
    rev = "ddbe48383984d56acd9e1ab6a090c54ca6b735a6";
    hash = "sha256-M1G7ypcfs7nJmXgkyoG96jT/CkgN5BOzy+DGO4LVCvA=";
  };
  xbyak = fetchFromGitHub {
    owner = "herumi";
    repo = "xbyak";
    rev = "44a72f369268f7d552650891b296693e91db86bb";
    hash = "sha256-S4arAwbhTGsUhDFfy5fTGyDvCm0/x/LKiiPTAuRM8Yk=";
  };
  zydis = fetchFromGitHub {
    owner = "zyantific";
    repo = "zydis";
    rev = "120e0e705f8e3b507dc49377ac2879979f0d545c";
    fetchSubmodules = true; # zycore
    hash = "sha256-bjQCaYRA94CGBsxG+UOuDDyLrH3k2ERJbn0+7ITGLeU=";
  };
  zstd = fetchFromGitHub {
    owner = "facebook";
    repo = "zstd";
    rev = "f8745da6ff1ad1e7bab384bd1f9d742439278e99";
    hash = "sha256-tNFWIT9ydfozB8dWcmTMuZLCQmQudTFJIkSr0aG7S44=";
  };
  zarchive = fetchFromGitHub {
    owner = "Exzap";
    repo = "ZArchive";
    rev = "d2c717730092c7bf8cbb033b12fd4001b7c4d932";
    hash = "sha256-hX637O/mVLTzmG0a9swJu9w+3o26VHo+K/9RhMuf1lI=";
  };

  # O submódulo ext-ffmpeg-core não compila o FFmpeg: no configure ele baixa
  # as libs estáticas que o próprio upstream publica como release, com nome
  # igual ao commit do submódulo (git rev-parse --short=12). Mesmo binário,
  # só que fixado por hash e entregue via FFMPEG_PREBUILT_DIR.
  ffmpeg-core = fetchzip {
    url = "https://github.com/KytyPS5/ext-ffmpeg-core/releases/download/9ac4cfd195f1/ffmpeg-linux-x64.zip";
    stripRoot = false;
    hash = "sha256-MX8Rifr6CvFFkm0IAmJPNGzLb8FG5HJJUKO/l0zegko=";
  };

  runtimeLibs = [
    # Launcher Qt 6: Concurrent, Network, Widgets e DBus estão no qtbase.
    qt6.qtbase
    qt6.qtwayland
    vulkan-loader

    # O SDL3 embutido descarta em silêncio áudio, hotplug de controle e o
    # backend Wayland quando faltam estas libs, em vez de falhar no configure.
    alsa-lib
    libpulseaudio
    dbus
    udev
    wayland
    # Decorações client-side; sem isto o SDL3 abre janela Wayland sem barra
    # de título em compositores que não decoram do lado do servidor.
    libdecor
    libxkbcommon

    libGL
    libx11
    libxcursor
    libxext
    libxfixes
    libxi
    libxrandr
    libxscrnsaver
    libxtst
  ];
in
stdenv.mkDerivation (finalAttrs: {
  pname = "kytyps5";
  version = "0.3.0-unstable-2026-10-09";

  __structuredAttrs = true;
  strictDeps = true;

  src = fetchFromGitHub {
    owner = "KytyPS5";
    repo = "KytyPS5";
    rev = "4c8fc53a8582543200caa697acad2a9f09937cec";
    fetchSubmodules = true;
    hash = "sha256-1Xhjg2j2ZeshWu5SE/gHme6wJIcoYxdKG+mTMkMRsfI=";
  };

  # O FetchContent não aplica PATCH_COMMAND quando a fonte vem de
  # FETCHCONTENT_SOURCE_DIR_*, então as cópias graváveis ficam dentro da
  # árvore e o patch do ZArchive é aplicado aqui. Sem .git, o
  # generate_version.cmake cairia em "unknown"; grava o commit fixado.
  postPatch = ''
    mkdir -p _deps
    cp -r ${opus} _deps/opus
    cp -r ${xbyak} _deps/xbyak
    cp -r ${zydis} _deps/zydis
    cp -r ${zstd} _deps/zstd
    cp -r ${zarchive} _deps/zarchive
    chmod -R u+w _deps

    # Os fontes do ZArchive são CRLF e o patch é LF (o upstream contorna com
    # `git apply --ignore-whitespace`). Converte os dois arquivos para LF.
    sed -i 's/\r$//' _deps/zarchive/include/zarchive/zarchivecommon.h \
      _deps/zarchive/src/zarchivereader.cpp
    patch -d _deps/zarchive -p1 < 3rdparty/patches/zarchive-reader.patch

    substituteInPlace src/generate_version.cmake \
      --replace-fail 'set(KYTY_GIT_VERSION "unknown")' 'set(KYTY_GIT_VERSION "${finalAttrs.version}")' \
      --replace-fail 'set(KYTY_GIT_HASH "unknown")' 'set(KYTY_GIT_HASH "${builtins.substring 0 7 finalAttrs.src.rev}")' \
      --replace-fail 'set(KYTY_GIT_REVISION "unknown")' 'set(KYTY_GIT_REVISION "${finalAttrs.src.rev}")'
  '';

  nativeBuildInputs = [
    cmake
    ninja
    # O CMakeLists do upstream força -fuse-ld=lld com clang. Tem que ser o
    # lld *embrulhado* (bintools): com o `lld` cru o clang chama o ld.lld
    # direto, o ld-wrapper do Nix não roda e os binários saem sem RPATH
    # (nem libstdc++ resolvem).
    llvmPackages.bintools
    pkg-config
    # O SPIRV-Tools embutido roda python3 no configure.
    python3
    # glslangValidator, para os shaders embutidos.
    glslang
    wayland-scanner
    makeWrapper
    copyDesktopItems
  ];

  buildInputs = runtimeLibs ++ [ wayland-protocols ];

  # O wrapper abaixo já cuida do QT_PLUGIN_PATH (e o launcher dispara o
  # kyty_emulator, que não é app Qt mas herda o ambiente).
  dontWrapQtApps = true;

  cmakeFlags = [
    (lib.cmakeBool "BUILD_TESTING" false)
    (lib.cmakeBool "FETCHCONTENT_FULLY_DISCONNECTED" true)
    (lib.cmakeFeature "FFMPEG_PREBUILT_DIR" "${ffmpeg-core}")
    # Impede o CMakeLists de pegar sccache/ccache do ambiente.
    (lib.cmakeFeature "CMAKE_C_COMPILER_LAUNCHER" "")
    (lib.cmakeFeature "CMAKE_CXX_COMPILER_LAUNCHER" "")
  ];

  # Caminhos absolutos para as cópias de _deps (o cwd aqui é a raiz do fonte).
  preConfigure = ''
    cmakeFlags+=(
      "-DFETCHCONTENT_SOURCE_DIR_OPUS=$PWD/_deps/opus"
      "-DFETCHCONTENT_SOURCE_DIR_XBYAK=$PWD/_deps/xbyak"
      "-DFETCHCONTENT_SOURCE_DIR_ZYDIS=$PWD/_deps/zydis"
      "-DFETCHCONTENT_SOURCE_DIR_ZSTD=$PWD/_deps/zstd"
      "-DFETCHCONTENT_SOURCE_DIR_ZARCHIVE_SOURCE=$PWD/_deps/zarchive"
    )
  '';

  # Só o launcher (que depende do kyty_emulator). O `all` arrastaria as
  # ferramentas de linha de comando do SPIRV-Tools e afins.
  ninjaFlags = [ "launcher" ];

  # O `cmake --install` do upstream empacota Qt e plugins dentro do prefixo
  # (para distribuir fora de distro). Aqui eles vêm do store, então só os
  # binários e os assets são copiados, no layout que o launcher espera:
  # kyty_emulator ao lado dele e assets/ ao lado do kyty_emulator.
  installPhase = ''
    runHook preInstall

    install -Dm755 launcher/launcher $out/lib/kytyps5/launcher
    install -Dm755 kyty_emulator $out/lib/kytyps5/kyty_emulator
    mkdir -p $out/lib/kytyps5/assets
    cp -r ../assets/sounds $out/lib/kytyps5/assets/

    install -Dm644 ../src/launcher/icons/trophy.svg \
      $out/share/icons/hicolor/scalable/apps/kytyps5.svg

    # As libs linkadas resolvem pelo RPATH; mas o SDL3 e o Qt fazem dlopen de
    # Vulkan, PulseAudio, Wayland, X11 e libdecor em runtime, então essas
    # também vão pelo ambiente.
    makeWrapper $out/lib/kytyps5/launcher $out/bin/kytyps5 \
      --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath runtimeLibs} \
      --prefix QT_PLUGIN_PATH : ${qt6.qtbase}/${qt6.qtbase.qtPluginPrefix}:${qt6.qtwayland}/${qt6.qtbase.qtPluginPrefix}

    runHook postInstall
  '';

  desktopItems = [
    (makeDesktopItem {
      name = "kytyps5";
      desktopName = "KytyPS5";
      comment = "PlayStation 5 translation layer";
      exec = "kytyps5";
      icon = "kytyps5";
      categories = [
        "Game"
        "Emulator"
      ];
      terminal = false;
    })
  ];

  meta = {
    description = "PlayStation 5 emulator (translation layer) with a Qt launcher";
    homepage = "https://github.com/KytyPS5/KytyPS5";
    license = lib.licenses.gpl2Only;
    mainProgram = "kytyps5";
    platforms = [ "x86_64-linux" ];
    maintainers = [ ];
  };
})
