{
  description = "git subtrees -- manage multiple git subtree prefixes with zero config";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        devShells.default = pkgs.mkShell {
          packages = [
            pkgs.git
            pkgs.bats
            pkgs.shellcheck
            pkgs.shfmt
            pkgs.bashInteractive
            pkgs.just
          ];

          shellHook = ''
            repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
            export PATH="$repo_root:$PATH"
          '';
        };
      });
}
