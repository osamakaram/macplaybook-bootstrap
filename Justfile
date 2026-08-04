set shell := ["bash", "-euo", "pipefail", "-c"]

default:
  @just --list

validate:
  bash -n bootstrap.sh tests/test-bootstrap.sh
  shellcheck bootstrap.sh tests/test-bootstrap.sh
  ./tests/test-bootstrap.sh
  git diff --check
  if command -v sonar >/dev/null 2>&1; then git ls-files --cached --others --exclude-standard -z | xargs -0 -n 1 sonar analyze secrets; fi
  if command -v gitleaks >/dev/null 2>&1; then gitleaks detect --no-banner --redact --source . && gitleaks dir --no-banner --redact .; fi
  if command -v trufflehog >/dev/null 2>&1; then trufflehog filesystem --no-update --exclude-paths=.trufflehog-exclude-paths.txt --fail --results=verified,unknown,unverified .; fi
