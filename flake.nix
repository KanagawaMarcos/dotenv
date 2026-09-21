{
  description = "Configuração NixOS do host nixos";

  inputs = {
    # Fixado na revisão que o canal já tinha quando a config migrou para
    # flake, para a primeira troca não virar um download de 12 GiB.
    # Para atualizar: nix flake update
    nixpkgs.url = "github:NixOS/nixpkgs/21a67dc470149f337cecafbe965d8d252a390518";
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
