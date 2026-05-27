#!/usr/bin/env bash
# bootstrap-crates.sh
# Pre-fetch Rust crates that crates.io blocks without a User-Agent header.
# Run this ONCE on any fresh NixOS-WSL instance before `nixos-rebuild switch`.
#
# Why: crates.io returns 403 for requests without User-Agent.
#      Nix's fetcher doesn't send one. nixos-wsl-utils needs these crates
#      compiled from source (not in the NixOS binary cache).

set -euo pipefail

echo "🦀 Fetching blocked crates with User-Agent header..."

CRATES=(
  "kernlog:0.3.1"
  "systemd-journal-logger:2.2.2"
)

for entry in "${CRATES[@]}"; do
  name="${entry%%:*}"
  version="${entry##*:}"
  filename="crate-${name}-${version}.tar.gz"
  url="https://crates.io/api/v1/crates/${name}/${version}/download"

  echo "  ↓ ${name} ${version}"
  curl -sL -H "User-Agent: Nix/2.31.2" -o "/tmp/${filename}" "${url}"

  if [ ! -s "/tmp/${filename}" ]; then
    echo "  ✗ Download failed or empty: ${filename}" >&2
    exit 1
  fi

  store_path=$(nix-prefetch-url --name "${filename}" "file:///tmp/${filename}" 2>&1 | grep "^path is" | cut -d"'" -f2)
  echo "  ✓ ${store_path:-added to store}"
done

echo ""
echo "✓ All crates pre-fetched. You can now run:"
echo "  sudo nixos-rebuild switch --flake /etc/nixos#nixos"
