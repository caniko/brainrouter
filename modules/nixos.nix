brainrouterFlake: {
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) mkEnableOption mkIf mkOption types;

  cfg = config.services.brainrouter;

  configYaml = pkgs.writeText "brainrouter.yaml" (
    builtins.toJSON {
      manifest = {
        base_url = cfg.manifest.baseUrl;
      }
      // lib.optionalAttrs (cfg.manifest.apiKeyEnv != null) {
        api_key_env = cfg.manifest.apiKeyEnv;
      };
      llama_swap = {
        base_url = cfg.llamaSwap.baseUrl;
        fallback_model = cfg.llamaSwap.fallbackModel;
      }
      // lib.optionalAttrs (cfg.llamaSwap.localModels != []) {
        local_models = cfg.llamaSwap.localModels;
      }
      // lib.optionalAttrs (cfg.llamaSwap.localSystemPrompt != null) {
        local_system_prompt = cfg.llamaSwap.localSystemPrompt;
      };
      bonsai = {
        model_path = cfg.bonsai.modelPath;
      };
      models = {
        path = cfg.modelsPath;
        shared_write = cfg.modelsSharedWrite;
      };
      review = {
        max_iterations = cfg.review.maxIterations;
        forced_mode = cfg.review.forcedMode;
      }
      // lib.optionalAttrs (cfg.review.forcedModel != null) {
        forced_model = cfg.review.forcedModel;
      };
    }
  );
in {
  options.services.brainrouter = {
    enable = mkEnableOption "brainrouter LLM routing proxy";

    package = mkOption {
      type = types.package;
      default = brainrouterFlake.packages.${pkgs.system}.brainrouter;
      defaultText = "brainrouter package from flake";
      description = "brainrouter package to use.";
    };

    port = mkOption {
      type = types.port;
      default = 9099;
      description = "TCP port for the proxy.";
    };

    listenAddress = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "Address to bind the TCP listener to.";
    };

    manifest = {
      baseUrl = mkOption {
        type = types.str;
        default = "http://127.0.0.1:2099/v1";
        description = "Base URL of the Manifest cloud LLM router.";
      };

      apiKeyEnv = mkOption {
        type = types.nullOr types.str;
        default = "MANIFEST_API_KEY";
        description = "Name of the env var holding the Manifest API key. Set to null if Manifest does not require auth.";
      };
    };

    llamaSwap = {
      baseUrl = mkOption {
        type = types.str;
        default = "http://127.0.0.1:8081/v1";
        description = "Base URL of the local llama-swap server.";
      };

      fallbackModel = mkOption {
        type = types.str;
        description = "Model key to use when falling back from Manifest.";
      };

      localModels = mkOption {
        type = types.listOf types.str;
        default = [];
        description = "Model keys served by llama-swap for direct local routing.";
      };

      localSystemPrompt = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Path to a custom system prompt file for local routing mode.";
      };
    };

    bonsai.modelPath = mkOption {
      type = types.str;
      description = "Path to the Bonsai GGUF model file.";
    };

    modelsPath = mkOption {
      type = types.str;
      default = "/opt/models";
      description = "Shared model storage directory.";
    };

    modelsSharedWrite = mkOption {
      type = types.bool;
      default = false;
      description = "Allow all members of the aistack group to write to the models directory.";
    };

    review = {
      maxIterations = mkOption {
        type = types.int;
        default = 5;
        description = "Maximum LLM review iterations before escalating to human.";
      };

      forcedMode = mkOption {
        type = types.enum ["auto" "cloud" "local"];
        default = "auto";
        description = "Forced review mode.";
      };

      forcedModel = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Forced model key for local review mode.";
      };
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Open the firewall for the brainrouter TCP port.";
    };

    environmentFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to an environment file containing the Manifest API key and other secrets.";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [cfg.package];

    systemd.services.brainrouter = {
      description = "brainrouter LLM routing proxy";
      after = ["network-online.target"];
      wants = ["network-online.target"];
      wantedBy = ["multi-user.target"];

      serviceConfig = {
        ExecStart = "${cfg.package}/bin/brainrouter serve --config ${configYaml} --tcp-addr ${cfg.listenAddress}:${toString cfg.port}";
        Restart = "on-failure";
        RestartSec = 5;
        DynamicUser = true;
        NoNewPrivileges = true;
        RuntimeDirectory = "brainrouter";
        StateDirectory = "brainrouter";
        ProtectHome = true;
        ProtectSystem = "strict";
        PrivateTmp = true;
      };

      environment = {
        BRAINROUTER_CONFIG = "${configYaml}";
      };
    }
    // lib.optionalAttrs (cfg.environmentFile != null) {
      serviceConfig.EnvironmentFile = cfg.environmentFile;
    };

    networking.firewall = mkIf cfg.openFirewall {
      allowedTCPPorts = [cfg.port];
    };
  };
}
