# Overlay temporário para o uvtools.
#
# Enviado em https://github.com/NixOS/nixpkgs/pull/565611
# Quando o PR mergear e chegar ao canal, apague este diretório e remova a
# linha correspondente em nixpkgs.overlays no configuration.nix.
#
# A expressão aqui é cópia da do PR, com meta.maintainers esvaziado —
# a entrada `kanagawamarcos` em maintainer-list.nix só passa a existir no
# nixpkgs depois do merge.
#
# O deps.json NÃO é o do PR: foi regerado contra o nixpkgs travado no
# flake.lock. O lockfile do .NET amarra as versões exatas dos runtime/ref
# packs que o SDK pede, e o SDK daqui (10.0.400) pede 8.0.30/9.0.19,
# enquanto o do master pede 8.0.31/9.0.20 — com o arquivo do PR o restore
# falha com NU1102. Se atualizar o nixpkgs do flake e o build quebrar
# assim de novo, regere:
#
#   nix build .#nixosConfigurations.nixos.pkgs.uvtools.passthru.fetch-deps
#   ./result $PWD/overlays/uvtools/deps.json

final: _prev: {
  uvtools = final.callPackage ./uvtools.nix { };
}
