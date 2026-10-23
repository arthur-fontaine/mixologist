{
  description = "mixologist dev environment";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs =
    { nixpkgs, ... }:
    let
      forAllSystems = nixpkgs.lib.genAttrs [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];
    in
    {
      devShells = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShell {
            packages = [ pkgs.opencode ];

            # opencode's built-in "opencode" provider picks up OPENCODE_API_KEY from the environment.
            shellHook = ''
              if [ -f .env ]; then
                set -a
                . ./.env
                set +a
              fi
            '';
          };
        }
      );
    };
}
