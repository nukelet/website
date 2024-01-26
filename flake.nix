{
    description = "nukelet's personal website";

    inputs = {
        nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    };

    outputs = { self, nixpkgs }:
    let
        system = "x86_64-linux";
        pkgs = import nixpkgs { inherit system; };
    in
    {
        packages.${system}.default = pkgs.stdenv.mkDerivation {
            inherit system;
            name = "nukelet-website";
            src = ./.;
            nativeBuildInputs = [ pkgs.hugo ];
            buildPhase = "cd site && hugo";
            installPhase = "cp -r public $out";
        };

        devShells.${system}.default = pkgs.mkShell {
            inherit system;
            name = "nukelet-website";
            NIX_CONFIG = "experimental-features = nix-command flakes";
            packages = with pkgs; [
                hugo
            ];
        };
    };
}
