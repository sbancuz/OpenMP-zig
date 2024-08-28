{
  description = "Python shell flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        lib = nixpkgs.lib;
      in
      {
        devShells.default = pkgs.mkShell {
          packages = with pkgs;
            [
              zig
              zls

              llvmPackages_18.openmp
              llvmPackages_18.clang
              llvmPackages_18.llvm
              perl
              cmake
            ];
        };
      }
    );
}
