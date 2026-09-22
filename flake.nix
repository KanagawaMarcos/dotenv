{
  description = "Configuração NixOS do host nixos";

  inputs = {
    # Fixado na revisão que o canal já tinha quando a config migrou para
    # flake, para a primeira troca não virar um download de 12 GiB.
    # Para atualizar: nix flake update
    nixpkgs.url = "github:NixOS/nixpkgs/21a67dc470149f337cecafbe965d8d252a390518";

    # Segundo nixpkgs, no canal unstable, para os poucos pacotes que a gente
    # quer sempre na versão mais nova (hoje: gimp). O sistema continua vindo
    # do `nixpkgs` acima — só os pacotes marcados com `unstable.` usam este.
    #
    # Isto NÃO se atualiza sozinho: aponta para um branch, mas a revisão fica
    # travada no flake.lock. Para puxar a versão nova:
    #
    #   nix flake update nixpkgs-unstable   # só este input
    #   sudo nixos-rebuild switch --flake ~/Git/dotenv#nixos
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    inputs@{ self, nixpkgs, ... }:
    {
      nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        # Entrega os inputs aos módulos, para o configuration.nix poder
        # apontar nixPath e registry para esta mesma revisão de nixpkgs.
        specialArgs = { inherit inputs; };
        modules = [
          ./configuration.nix
        ];
      };
    };
}
