#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bootstrap="$repo_root/bootstrap.sh"
tmp_root="$(mktemp -d)"
cleanup() { rm -rf "$tmp_root"; }
trap cleanup EXIT HUP INT TERM

make_mock_gh() {
  local destination="$1"
  mkdir -p "$(dirname "$destination")"
  cat > "$destination" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  --version) printf 'gh version 2.97.0 (fixture)\n' ;;
  auth)
    case "${2:-}" in
      status) [[ "${MOCK_GH_AUTH:-ok}" == ok ]] ;;
      login) [[ "${MOCK_GH_LOGIN:-ok}" == ok ]] ;;
      setup-git) exit 0 ;;
    esac
    ;;
  *) printf 'ERROR: unexpected gh fixture invocation: %s\n' "$*" >&2; exit 2 ;;
esac
SH
  chmod 0755 "$destination"
}

base_env=(
  MACPLAYBOOK_TEST_MODE=true
  MACPLAYBOOK_ARCHITECTURE_OVERRIDE=arm64
  MACPLAYBOOK_CLT_AVAILABLE=true
  MACPLAYBOOK_SKIP_UPDATE=true
)

# Unsupported architecture fails before any installation.
if env "${base_env[@]}" MACPLAYBOOK_ARCHITECTURE_OVERRIDE=x86_64 "$bootstrap" >/dev/null 2>&1; then
  printf 'ERROR: unsupported architecture was accepted\n' >&2
  exit 1
fi

# Missing CLT exits cleanly and instructs a rerun.
env "${base_env[@]}" MACPLAYBOOK_CLT_AVAILABLE=false "$bootstrap" > "$tmp_root/clt.out"
grep -q 'rerun this exact command' "$tmp_root/clt.out"

# Checksum failure is fatal.
mkdir -p "$tmp_root/checksum-bin"
fake_curl_dir="$tmp_root/fake-curl"
mkdir -p "$fake_curl_dir"
cat > "$fake_curl_dir/curl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
output=""
while (( $# )); do
  [[ "$1" == -o ]] && { output="$2"; shift 2; continue; }
  shift
done
printf 'not a GitHub CLI archive\n' > "$output"
SH
chmod 0755 "$fake_curl_dir/curl"
if env "${base_env[@]}" PATH="$fake_curl_dir:/usr/bin:/bin" MACPLAYBOOK_LOCAL_BIN="$tmp_root/checksum-bin" MACPLAYBOOK_GH_SHA256_OVERRIDE=0000000000000000000000000000000000000000000000000000000000000000 "$bootstrap" >/dev/null 2>&1; then
  printf 'ERROR: invalid GitHub CLI checksum was accepted\n' >&2
  exit 1
fi

# Existing matching clean clone is accepted and handed off.
fixture_bin="$tmp_root/local-bin"
make_mock_gh "$fixture_bin/gh"
fixture_repo="$tmp_root/macplaybook"
mkdir -p "$fixture_repo"
git -C "$fixture_repo" init -q -b main
git -C "$fixture_repo" remote add origin https://github.com/osamakaram/macplaybook.git
cat > "$fixture_repo/bootstrap.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'private handoff complete\n'
SH
chmod 0755 "$fixture_repo/bootstrap.sh"
git -C "$fixture_repo" add bootstrap.sh
git -C "$fixture_repo" -c user.name=Fixture -c user.email=fixture@example.invalid commit -qm initial
env "${base_env[@]}" MACPLAYBOOK_LOCAL_BIN="$fixture_bin" MACPLAYBOOK_DESTINATION="$fixture_repo" "$bootstrap" > "$tmp_root/matching.out"
grep -q 'private handoff complete' "$tmp_root/matching.out"

# Dirty matching clone is refused.
printf 'dirty\n' >> "$fixture_repo/bootstrap.sh"
if env "${base_env[@]}" MACPLAYBOOK_LOCAL_BIN="$fixture_bin" MACPLAYBOOK_DESTINATION="$fixture_repo" "$bootstrap" >/dev/null 2>&1; then
  printf 'ERROR: dirty checkout was accepted\n' >&2
  exit 1
fi
git -C "$fixture_repo" restore bootstrap.sh

# Unrelated clone is refused.
git -C "$fixture_repo" remote set-url origin https://github.com/example/unrelated.git
if env "${base_env[@]}" MACPLAYBOOK_LOCAL_BIN="$fixture_bin" MACPLAYBOOK_DESTINATION="$fixture_repo" "$bootstrap" >/dev/null 2>&1; then
  printf 'ERROR: unrelated checkout was accepted\n' >&2
  exit 1
fi

# Failed authentication is fatal.
git -C "$fixture_repo" remote set-url origin https://github.com/osamakaram/macplaybook.git
if env "${base_env[@]}" MOCK_GH_AUTH=fail MOCK_GH_LOGIN=fail MACPLAYBOOK_LOCAL_BIN="$fixture_bin" MACPLAYBOOK_DESTINATION="$fixture_repo" "$bootstrap" >/dev/null 2>&1; then
  printf 'ERROR: failed GitHub authentication was ignored\n' >&2
  exit 1
fi

printf 'Public bootstrap fixture tests passed\n'
