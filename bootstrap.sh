#!/usr/bin/env bash
set -euo pipefail

gh_version="2.97.0"
gh_asset="gh_${gh_version}_macOS_arm64.zip"
gh_sha256="a58b8fd77b417a38f47a0b54d1370c59b0fcdb324ccc9ca002b0998f7c4c999e"
gh_url="https://github.com/cli/cli/releases/download/v${gh_version}/${gh_asset}"
local_bin="${MACPLAYBOOK_LOCAL_BIN:-$HOME/.local/bin}"
destination="${MACPLAYBOOK_DESTINATION:-$HOME/Code/osamakaram/macplaybook}"
repo_slug="${MACPLAYBOOK_REPO_SLUG:-osamakaram/macplaybook}"
test_mode="${MACPLAYBOOK_TEST_MODE:-false}"

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

architecture="${MACPLAYBOOK_ARCHITECTURE_OVERRIDE:-$(uname -m)}"
[[ "$(uname -s)" == "Darwin" || "$test_mode" == true ]] || fail "macOS is required"
[[ "$architecture" == "arm64" ]] || fail "Only Apple Silicon is supported"

clt_available="${MACPLAYBOOK_CLT_AVAILABLE:-auto}"
if [[ "$clt_available" == auto ]]; then
  xcode-select -p >/dev/null 2>&1 && clt_available=true || clt_available=false
fi
if [[ "$clt_available" != true ]]; then
  if [[ "$test_mode" != true ]]; then
    xcode-select --install >/dev/null 2>&1 || true
  fi
  printf 'Xcode Command Line Tools installation was requested. Complete Apple\047s installer, then rerun this exact command.\n'
  exit 0
fi

mkdir -p "$local_bin"
gh_bin="$local_bin/gh"
if [[ ! -x "$gh_bin" ]] || ! "$gh_bin" --version 2>/dev/null | head -n 1 | grep -Fq "gh version ${gh_version}"; then
  tmp_dir="$(mktemp -d)"
  cleanup() { rm -rf "$tmp_dir"; }
  trap cleanup EXIT HUP INT TERM
  curl --proto '=https' --tlsv1.2 -fsSL "$gh_url" -o "$tmp_dir/$gh_asset"
  printf '%s  %s\n' "${MACPLAYBOOK_GH_SHA256_OVERRIDE:-$gh_sha256}" "$tmp_dir/$gh_asset" | shasum -a 256 -c -
  ditto -x -k "$tmp_dir/$gh_asset" "$tmp_dir/extracted"
  install -m 0755 "$tmp_dir/extracted/gh_${gh_version}_macOS_arm64/bin/gh" "$gh_bin"
  rm -rf "$tmp_dir"
  trap - EXIT HUP INT TERM
fi

if ! "$gh_bin" auth status >/dev/null 2>&1; then
  "$gh_bin" auth login --hostname github.com --git-protocol https --web || fail "GitHub authentication did not complete"
fi
"$gh_bin" auth status >/dev/null 2>&1 || fail "GitHub authentication is unavailable"
"$gh_bin" auth setup-git

normalize_remote() {
  printf '%s\n' "$1" | sed -E \
    -e 's#^git@github\.com:#https://github.com/#' \
    -e 's#^ssh://git@github\.com/#https://github.com/#' \
    -e 's#\.git$##' \
    -e 's#/$##'
}

expected_remote="$(normalize_remote "https://github.com/${repo_slug}.git")"
if [[ -e "$destination" ]]; then
  [[ -d "$destination/.git" ]] || fail "Destination exists but is not a Git checkout: $destination"
  actual_remote="$(normalize_remote "$(git -C "$destination" remote get-url origin 2>/dev/null || true)")"
  [[ "$actual_remote" == "$expected_remote" ]] || fail "Destination is an unrelated checkout: $actual_remote"
  [[ -z "$(git -C "$destination" status --porcelain)" ]] || fail "Destination is dirty; commit, stash, or remove the changes before rerunning"
  [[ "$(git -C "$destination" branch --show-current)" == "main" ]] || fail "Existing checkout must be on main"
  if [[ "${MACPLAYBOOK_SKIP_UPDATE:-false}" != true ]]; then
    git -C "$destination" fetch origin main
    git -C "$destination" merge --ff-only origin/main
  fi
else
  mkdir -p "$(dirname "$destination")"
  "$gh_bin" repo clone "$repo_slug" "$destination"
fi

[[ -x "$destination/bootstrap.sh" ]] || fail "Private playbook bootstrap is missing or not executable"
exec "$destination/bootstrap.sh" "$@"
