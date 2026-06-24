{
  description = "brainrouter — Bonsai-routed LLM failover proxy";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    crane = {
      url = "github:ipetkov/crane";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # crane's nixpkgs follows nixpkgs-unstable internally;
    # the follow above lets flake.lock pin it consistently.
    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    self,
    nixpkgs,
    crane,
    fenix,
    flake-utils,
    ...
  }:
    flake-utils.lib.eachDefaultSystem (system: let
      pkgs = import nixpkgs {
        inherit system;
        overlays = [fenix.overlays.default];
      };

      craneLib = crane.mkLib pkgs;

      # llvm/clang for llama-cpp-2 bindgen
      llvmPackages = pkgs.llvmPackages_21;

      nativeBuildInputs = with pkgs; [
        clang_21
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
        src = craneLib.path {
          path = ./.;
          extraFilter = path: type:
            builtins.any (ext: nixpkgs.lib.strings.hasSuffix ext path) [".html" ".svg"]
            || craneLib.path.defaultFilter path type;
        };
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
    in {
      packages.default = brainrouter;
      packages.brainrouter = brainrouter;

      checks = {
        inherit brainrouter;
      };
    })
    // {
      nixosModules.default = import ./modules/nixos.nix self;
    };
}
