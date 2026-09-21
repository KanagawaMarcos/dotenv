# Overlay temporário para o rayforge e as quatro bibliotecas Python que ele
# precisa e que ainda não existem no nixpkgs.
#
# Enviado em https://github.com/NixOS/nixpkgs/pull/565514
# Quando o PR mergear e chegar ao canal, apague este diretório e remova a
# linha correspondente em nixpkgs.overlays no configuration.nix.
#
# As expressões aqui são cópias das do PR, com meta.maintainers esvaziado —
# a entrada `kanagawamarcos` em maintainer-list.nix só passa a existir no
# nixpkgs depois do merge.

final: prev: {
  python3 = prev.python3.override (old: {
    self = final.python3;
    packageOverrides = final.lib.composeExtensions (old.packageOverrides or (_: _: { })) (
      pyfinal: _pyprev: {
        asyncudp = pyfinal.callPackage ./asyncudp.nix { };
        raygeo = pyfinal.callPackage ./raygeo.nix { };
        ruida-pa = pyfinal.callPackage ./ruida-pa.nix { };
        vtracer = pyfinal.callPackage ./vtracer.nix { };
      }
    );
  });

  python3Packages = final.python3.pkgs;

  rayforge = final.callPackage ./rayforge.nix { };
}
