---
name: hermes-nixos-wsl
description: Deploy Hermes Agent (Nous Research) on NixOS-WSL with full NixOS module, Copilot provider, and portable state management. Use when setting up Hermes on a new NixOS-WSL instance, migrating Hermes between machines, troubleshooting the NixOS Hermes module, or bootstrapping a Dev Box for Hermes.
---

# Hermes Agent on NixOS-WSL

Deploy Nous Research's Hermes Agent as a declarative NixOS service inside WSL2, with GitHub Copilot as the primary LLM provider. The system is reproducible — one `git clone` + `nixos-rebuild switch` recreates everything.

## Architecture

```
Dev Box / Windows Host (corp-managed, DLP-compliant)
└── NixOS-WSL 25.11 (flake-based, reproducible)
    └── Hermes Agent (NixOS module, systemd service)
        ├── Identity: SOUL.md, memories/, skills/ (git-tracked)
        ├── State: state.db, sessions/ (volume, not in git)
        ├── Provider: GitHub Copilot (primary) + OpenRouter (fallback)
        └── Access: terminal (VS Code Remote) → Teams later
```

## Prerequisites

- Windows 10/11 with WSL2 enabled (`wsl --install --no-distribution`)
- GitHub account with Copilot subscription
- Private git repo for Hermes identity files

## Quick Start (New Instance)

### 1. Install NixOS-WSL

From PowerShell:
```powershell
Invoke-WebRequest -Uri "https://github.com/nix-community/NixOS-WSL/releases/download/2511.7.1/nixos.wsl" -OutFile "$env:TEMP\nixos.wsl"
& "$env:TEMP\nixos.wsl"
# Or: wsl --import NixOS "$env:USERPROFILE\NixOS" "$env:TEMP\nixos.wsl"
```

Launch: `wsl -d NixOS`

### 2. Bootstrap crates.io access

**Critical:** Corporate networks and crates.io both block requests without a User-Agent header (403). Run this before any `nixos-rebuild`:

```bash
bash /path/to/this/skill/scripts/bootstrap-crates.sh
```

Or manually:
```bash
curl -L -H "User-Agent: Nix/2.31.2" -o /tmp/crate-kernlog-0.3.1.tar.gz \
  "https://crates.io/api/v1/crates/kernlog/0.3.1/download"
curl -L -H "User-Agent: Nix/2.31.2" -o /tmp/crate-systemd-journal-logger-2.2.2.tar.gz \
  "https://crates.io/api/v1/crates/systemd-journal-logger/2.2.2/download"
nix-prefetch-url --name crate-kernlog-0.3.1.tar.gz file:///tmp/crate-kernlog-0.3.1.tar.gz
nix-prefetch-url --name crate-systemd-journal-logger-2.2.2.tar.gz file:///tmp/crate-systemd-journal-logger-2.2.2.tar.gz
```

### 3. Write NixOS configuration

```bash
sudo tee /etc/nixos/flake.nix << 'EOF'
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixos-wsl = {
      url = "github:nix-community/NixOS-WSL/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hermes-agent = {
      url = "github:NousResearch/hermes-agent";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, nixos-wsl, hermes-agent, ... }: {
    nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        nixos-wsl.nixosModules.default
        hermes-agent.nixosModules.default
        ./configuration.nix
      ];
    };
  };
}
EOF
```

```bash
sudo tee /etc/nixos/configuration.nix << 'EOF'
{ config, lib, pkgs, ... }:

{
  wsl.enable = true;
  wsl.defaultUser = "nixos";

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  environment.systemPackages = with pkgs; [
    git
    gh
    curl
    vim
  ];

  services.hermes-agent = {
    enable = true;
    addToSystemPackages = true;
    user = "nixos";
    group = "users";
    createUser = false;
    stateDir = "/home/nixos";
  };

  system.stateVersion = "25.11";
}
EOF
```

### 4. Build and switch

```bash
sudo nixos-rebuild switch --flake /etc/nixos#nixos
```

### 5. Authenticate and clone identity

```bash
# GitHub auth (provides Copilot token)
gh auth login

# Clone your hermes identity repo
git clone https://github.com/duncanbeard_microsoft/hermes.git ~/.hermes
```

### 6. Migrate state from Windows (if applicable)

```bash
# Session history (SQLite)
cp /mnt/c/Users/duncanbeard/AppData/Local/hermes/state.db ~/.hermes/state.db

# Memories
cp /mnt/c/Users/duncanbeard/AppData/Local/hermes/memories/MEMORY.md ~/.hermes/memories/
cp /mnt/c/Users/duncanbeard/AppData/Local/hermes/memories/USER.md ~/.hermes/memories/

# OAuth tokens (optional, saves re-auth)
cp /mnt/c/Users/duncanbeard/AppData/Local/hermes/auth.json ~/.hermes/auth.json 2>/dev/null
```

### 7. Run setup wizard

```bash
hermes setup
```

This auto-detects Copilot models and configures the provider. Skip TTS/browser installs (they fail on NixOS immutable store — add via `extraPackages` in configuration.nix if needed later).

### 8. Launch

```bash
hermes
```

## Configuration Notes

### Provider setup (config.yaml)

```yaml
model:
  provider: copilot-acp
  default: claude-opus-4.7-1m-internal
  api_mode: chat_completions
  base_url: acp://copilot

# Optional: fallback when Copilot rate-limits
# fallback_model:
#   provider: openrouter
#   model: anthropic/claude-sonnet-4
```

### Key paths

| Path | Contents | Backed up by |
|------|----------|--------------|
| `~/.hermes/SOUL.md` | Agent identity/personality | Git |
| `~/.hermes/memories/` | MEMORY.md, USER.md | Git |
| `~/.hermes/skills/` | Agent-created skills | Git |
| `~/.hermes/config.yaml` | Settings | Git (optional) |
| `~/.hermes/state.db` | Session history (SQLite WAL) | Infra snapshots |
| `~/.hermes/.env` | API keys, secrets | NOT in git |
| `/etc/nixos/` | System configuration | Git (same or separate repo) |

### NixOS module options

```bash
# List all available options
nix eval /etc/nixos#nixosConfigurations.nixos.options.services.hermes-agent --apply 'opt: builtins.attrNames opt'
```

Available: `addToSystemPackages`, `authFile`, `configFile`, `container`, `createUser`, `documents`, `enable`, `environment`, `environmentFiles`, `extraArgs`, `extraDependencyGroups`, `extraPackages`, `extraPlugins`, `extraPythonPackages`, `group`, `mcpServers`, `package`, `restart`, `restartSec`, `settings`, `stateDir`, `user`, `workingDirectory`

### Managed vs unmanaged mode

The NixOS module creates a `.managed` marker file in the hermes home. In managed mode:
- `hermes setup`, `config set`, `gateway install/uninstall` are blocked
- Config is generated from the module's `settings` attribute

**For existing users migrating from a git-based workflow:** Remove `.managed` to keep your own config.yaml as source of truth:
```bash
rm -f ~/.hermes/.managed
```

## Troubleshooting

### crates.io 403 on nixos-rebuild

**Cause:** crates.io rejects HTTP requests without a User-Agent header. Nix's fetcher doesn't send one. The `nixos-wsl-utils` package needs to compile Rust crates from source (not in binary cache).

**Fix:** Run `scripts/bootstrap-crates.sh` before rebuild.

**Permanent fix:** Set up a Cachix binary cache and push your built closure:
```bash
nix build /etc/nixos#nixosConfigurations.nixos.config.system.build.toplevel
cachix push your-cache ./result
```

### "unknown" model in hermes status bar

**Cause:** config.yaml missing or has parse errors (e.g., references to `127.0.0.1:13305` lemonade server).

**Fix:** Run `hermes setup` or `hermes doctor --fix` to regenerate config. Strip any `auxiliary:` block referencing local inference servers that don't exist.

### pip/npm install failures during hermes setup

**Cause:** NixOS store is immutable. The hermes setup wizard tries to `pip install` into the nix store, which is read-only.

**Fix:** These are optional packages (TTS, browser). Add them to `configuration.nix` via the module:
```nix
services.hermes-agent = {
  extraPythonPackages = ps: [ ps.piper-tts ];
  extraPackages = [ pkgs.nodePackages.camofox-browser ];
};
```

### User conflict on nixos-rebuild ("isSystemUser/isNormalUser")

**Cause:** The hermes module tries to create a user that already exists (e.g., "nixos").

**Fix:** Set `createUser = false` in the module config.

### Double-nested .hermes/.hermes path

**Cause:** When `stateDir = "/home/nixos/.hermes"`, the module creates hermes home at `stateDir/.hermes/`. But the interactive `hermes` command uses `~/.hermes/` directly.

**Fix:** Set `stateDir = "/home/nixos"` so the module uses `/home/nixos/.hermes/` as hermes home, matching the interactive command.

### Gateway service warnings

- **"No messaging platforms enabled"** — expected until you configure Teams/Telegram
- **"Stale systemd unit"** — the module's timeout doesn't match Hermes defaults; cosmetic
- **"No user allowlists"** — set `GATEWAY_ALLOW_ALL_USERS=true` in `.env` for local use

## Future work

- [ ] Add Teams integration via Azure Bot Service (requires public HTTPS endpoint)
- [ ] Set up Cachix binary cache for zero-fight rebuilds
- [ ] Migrate to agenix for secrets management
- [ ] Add `extraPythonPackages` for optional tools (piper-tts, etc.)
- [ ] File upstream NixOS-WSL issue for User-Agent in crate fetching
