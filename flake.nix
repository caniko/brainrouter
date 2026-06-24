{
  description = "brainrouter — Bonsai-routed LLM failover proxy";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    rs-harbor = {
      url = "git+https://codeberg.org/caniko/rs-harbor.git";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    self,
    nixpkgs,
    rs-harbor,
    rust-overlay,
    flake-utils,
    ...
  }: let
    # Build the brainrouter package once, reuse it in outputs and
    # in the NixOS module closure below.
    forAllSystems = flake-utils.lib.eachDefaultSystem;

    mkBrainrouter = system: let
      pkgs = import nixpkgs {
        inherit system;
        overlays = [rust-overlay.overlays.default];
      };

      toolchain = rs-harbor.lib.mkToolchain {
        inherit pkgs;
        channel = "stable";
      };
      inherit (toolchain) craneLib;

      # Use nixpkgs's default llvmPackages for the current channel
      # instead of pinning llvmPackages_21.
      llvmPackages = pkgs.llvmPackages;

      nativeBuildInputs = with pkgs; [
        clang
        cmake
        llvmPackages.libclang
        pkg-config
        shaderc
      ];

      buildInputs = with pkgs; [
        openssl
        vulkan-loader
        vulkan-headers
      ];

      LIBCLANG_PATH = "${llvmPackages.libclang.lib}/lib";

      BINDGEN_EXTRA_CLANG_ARGS =
        "-isystem ${llvmPackages.libclang.lib}/lib/clang/${llvmPackages.libclang.version}/include";

      commonArgs = {
        src = craneLib.path ./.;
        pname = "brainrouter";
        version = "1.1.2";
        strictDeps = true;
        inherit nativeBuildInputs buildInputs LIBCLANG_PATH BINDGEN_EXTRA_CLANG_ARGS;
        OPENSSL_NO_VENDOR = 1;
      };

      cargoArtifacts = craneLib.buildDepsOnly commonArgs;

      brainrouter = craneLib.buildPackage (commonArgs
        // {
          inherit cargoArtifacts;
        });
    in brainrouter;
  in
    forAllSystems (system: let
      brainrouter = mkBrainrouter system;
    in {
      packages.default = brainrouter;
      packages.brainrouter = brainrouter;

      checks = {
        inherit brainrouter;
      };
    })
    // {
      # NixOS module closes over the x86_64 package — the only arch
      # brainrouter targets. Consumers override via services.brainrouter.package
      # if needed.
      nixosModules.default = import ./modules/nixos.nix {
        brainrouterPkg = self.packages.x86_64-linux.brainrouter;
        inherit (nixpkgs) lib;
      };
    };
}
