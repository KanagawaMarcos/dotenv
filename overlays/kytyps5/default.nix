# Overlay para o KytyPS5 (emulador de PS5).
#
# Não existe no nixpkgs e o upstream não publica binário Linux, então é
# compilado do fonte, travado num commit (ver kytyps5.nix). Substitui o
# antigo ~/Git/kytyps5-nix, que compilava a partir de um checkout local.
#
# Para atualizar: troque `rev` e `version` em kytyps5.nix, ponha
# `hash = lib.fakeHash;`, rode o build e copie o hash que o Nix reclamar.
# Confira também os GIT_TAG do 3rdparty/CMakeLists.txt do upstream — as
# dependências baixadas por FetchContent estão fixadas lá e aqui.

final: _prev: {
  # O upstream só é testado com clang (o devshell dele usa clang + lld).
  kytyps5 = final.callPackage ./kytyps5.nix { stdenv = final.clangStdenv; };
}
