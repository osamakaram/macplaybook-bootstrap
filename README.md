# macplaybook-bootstrap

Public, minimal bootstrap for the private `osamakaram/macplaybook` repository.
It installs a pinned GitHub CLI binary after SHA-256 verification, performs
GitHub web authentication, validates or clones the private playbook, and hands
off to its pinned standalone Ansible bootstrap.

## One-line bootstrap

The supported entrypoint is pinned to the immutable `v1.0.0` tag:

```sh
/bin/bash -c "$(curl --proto '=https' --tlsv1.2 -fsSL https://raw.githubusercontent.com/osamakaram/macplaybook-bootstrap/v1.0.0/bootstrap.sh)"
```

Review [`bootstrap.sh`](bootstrap.sh) before running it. The script:

- supports Apple Silicon macOS only;
- never installs Homebrew;
- exits cleanly if Xcode Command Line Tools need Apple's installer;
- places GitHub CLI 2.97.0 in `~/.local/bin` after checking SHA-256;
- uses GitHub web/device authentication and Keychain-backed `gh` storage;
- refuses dirty, unrelated, non-`main`, or non-Git destinations;
- hands off to `~/Code/osamakaram/macplaybook/bootstrap.sh`.

The public repository contains no personal inventory, private repository
contents, credentials, licenses, or recovery material.
