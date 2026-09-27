{
  description = "Orca for Even G2 — MoonBit app, Cloudflare Worker relay and Mac bridge";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      lib = nixpkgs.lib;
      lock = lib.importJSON ./nix/moonbit.lock.json;
      systems = builtins.attrNames lock.moonbit.platforms;

      # KEY=VALUE lines shared with scripts/fetch-sdk.sh.
      sdk = lib.pipe (builtins.readFile ./scripts/sdk.env) [
        (lib.splitString "\n")
        (builtins.filter (line: builtins.match "[A-Z_]+=.*" line != null))
        (map (
          line:
          let
            m = builtins.match "([A-Z_]+)=(.*)" line;
          in
          lib.nameValuePair (builtins.elemAt m 0) (builtins.elemAt m 1)
        ))
        builtins.listToAttrs
      ];

      # Only these unfree packages are allowed, by name.
      pkgsFor =
        system:
        import nixpkgs {
          inherit system;
          config.allowUnfreePredicate =
            pkg:
            builtins.elem (lib.getName pkg) [
              "moonbit"
              "terraform"
            ];
        };
      forEach = f: lib.genAttrs systems (system: f (pkgsFor system));

      build =
        pkgs:
        rec {
          moonbit = pkgs.callPackage ./nix/moonbit.nix { inherit lock; };
          even-g2-orca = pkgs.callPackage ./nix/package.nix { inherit moonbit sdk; };

          bridge = pkgs.writeShellApplication {
            name = "even-g2-orca-bridge";
            runtimeInputs = [ pkgs.nodejs_24 ];
            # Reads ./.env when present (see .env.example).
            text = ''exec node --env-file-if-exists=.env ${even-g2-orca}/bridge/bridge.js "$@"'';
          };

          # Run from the repository root after `nix run .#deploy`.
          tunnel = pkgs.writeShellApplication {
            name = "even-g2-orca-tunnel";
            runtimeInputs = [
              pkgs.cloudflared
              pkgs.terraform
            ];
            text = ''
              TUNNEL_TOKEN="''${TUNNEL_TOKEN:-$(terraform -chdir=infra output -raw tunnel_token)}"
              export TUNNEL_TOKEN
              exec cloudflared tunnel --no-autoupdate run
            '';
          };

          deploy = pkgs.writeShellApplication {
            name = "even-g2-orca-deploy";
            runtimeInputs = [ pkgs.terraform ];
            text = ''
              terraform -chdir=infra init -input=false
              terraform -chdir=infra apply -var "dist_dir=${even-g2-orca}" "$@"
            '';
          };

          update-moonbit = pkgs.writeShellApplication {
            name = "update-moonbit";
            runtimeInputs = [
              pkgs.jq
              pkgs.nix
            ];
            text = builtins.readFile ./nix/update-moonbit.sh;
          };
        };
    in
    {
      packages = forEach (
        pkgs:
        let
          b = build pkgs;
        in
        {
          inherit (b) moonbit even-g2-orca bridge;
          default = b.even-g2-orca;
        }
      );

      apps = forEach (
        pkgs:
        let
          b = build pkgs;
          app = drv: {
            type = "app";
            program = lib.getExe drv;
          };
        in
        {
          bridge = app b.bridge;
          tunnel = app b.tunnel;
          deploy = app b.deploy;
          update-moonbit = app b.update-moonbit;
          default = app b.bridge;
        }
      );

      checks = forEach (
        pkgs:
        let
          b = build pkgs;
        in
        {
          build = b.even-g2-orca;
          moon-test =
            pkgs.runCommand "even-g2-orca-moon-test"
              {
                nativeBuildInputs = [
                  b.moonbit
                  pkgs.nodejs_24
                ];
                src = lib.fileset.toSource {
                  root = ./.;
                  fileset = lib.fileset.unions [
                    ./moon.mod
                    ./core
                    ./js
                    ./app
                    ./bridge
                    ./worker
                  ];
                };
              }
              ''
                export HOME="$TMPDIR" MOON_HOME="$TMPDIR/.moon"
                cp -r "$src" work && chmod -R u+w work && cd work
                moon fmt --check
                moon test --target js --deny-warn
                touch "$out"
              '';
        }
      );

      devShells = forEach (
        pkgs:
        let
          b = build pkgs;
        in
        {
          default = pkgs.mkShell {
            packages = [
              b.moonbit
              pkgs.nodejs_24
              pkgs.terraform
              pkgs.cloudflared
              pkgs.openssl
              pkgs.jq
            ];
            shellHook = ''
              export MOON_HOME="''${MOON_HOME:-$HOME/.moon}"
            '';
          };
        }
      );

      formatter = forEach (pkgs: pkgs.nixfmt);
    };
}
