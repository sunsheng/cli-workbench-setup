# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Two parallel one-shot installers that provision the *same* modern CLI environment on two OSes:

- `install.ps1` — Windows Server / Windows, via [Scoop](https://scoop.sh).
- `install-ubuntu.sh` — Ubuntu Server, via `apt`.

They are deliberate mirrors: the same tool set (git, gh, ripgrep, fd, bat, fzf, jq, 7zip, eza, vim, zoxide, Node.js LTS, Codex CLI, Claude Code CLI), the same idempotent step structure, the same AI-CLI install strategy, and the same SSH hardening posture. **When you change behavior on one side, check whether the other side needs the mirror change** (and update `README.md`, which documents both). `config/` holds the shipped dotfiles consumed by both.

`README.md` is the user-facing doc and is written in Chinese — keep it in sync with any behavior change.

## Commands

There is no build and no unit-test framework. Validation = lint + a real install-and-verify, mirrored in `.github/workflows/ci.yml`.

Lint (run before pushing):

```bash
# Bash side
bash -n install-ubuntu.sh config/bashrc
shellcheck -s bash install-ubuntu.sh config/bashrc
```

```powershell
# PowerShell side: parse, then analyze (Error severity gates CI)
[System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path install.ps1), [ref]$null, [ref]([ref]$null).Value)
Invoke-ScriptAnalyzer -Path . -Recurse -Severity Error
```

Run an installer locally (both are safe to re-run — every step checks for an existing install first):

```bash
bash ./install-ubuntu.sh                 # full run
bash ./install-ubuntu.sh --no-profile    # tools only, no bash/vim config
bash ./install-ubuntu.sh --no-ssh        # skip OpenSSH config
NODE_MAJOR=22 bash ./install-ubuntu.sh   # pin Node major version
```

```powershell
.\install.ps1            # full run (SSH step auto-skips in a non-admin session)
.\install.ps1 -NoProfile
.\install.ps1 -NoSsh
```

CI (`ubuntu-latest` + `windows-latest`) runs the installer with `--no-ssh` / `-NoSsh`, then asserts every CLI is on `PATH` and that the profile defines the `ll` / git-shortcut functions. If you add a tool or a profile function, add it to the verify lists in `ci.yml`.

## Conventions that span files

**Idempotency is mandatory.** Every step must detect an existing install/config and skip (`command_exists` / `Get-Command` guards, `skip`/`Write-Skip`). Re-running must be a no-op.

**Config resolution: local-or-fetch.** Both installers can run from a clone *or* piped from `curl`/`iwr`. `resolve_config_file` (bash) / `Resolve-ConfigFile` (ps1) return the on-disk `config/<file>` when the script dir is known, otherwise download it from `REPO_RAW_BASE`/`$RepoRawBase` (the hardcoded `raw.githubusercontent.com/sunsheng/windows-cli-setup/main`). Keep that base URL correct if the repo moves.

**AI CLI install is a deliberate 3-tier fallback** (`install_claude_code_cli` / `Install-ClaudeCodeCli`, and the Codex equivalents):
1. Native binary pulled *directly* from `downloads.claude.ai` (resolve `latest` → download platform binary → verify SHA256 from `manifest.json` → run the binary's built-in `install`).
2. Official entry script (`claude.ai/install.*`).
3. `npm install -g`.
The native-first ordering is not arbitrary: `claude.ai/install.*` sits behind a Cloudflare managed challenge that **403s bare requests from datacenter/cloud IPs**, while `downloads.claude.ai` does not. Preserve this ordering and the checksum verification if you touch the installer.

**SSH hardening posture (both OSes).** Listen on port **58888 only** (22 intentionally dropped to dodge internet-wide brute force), **key-only auth** (`PasswordAuthentication no`), and a login-group allowlist. Ubuntu writes `/etc/ssh/sshd_config.d/99-cli-setup.conf` and neutralizes any earlier drop-in (e.g. cloud-init's `50-*.conf`) that re-enables password auth — sshd honors the *first* match, and `50-` sorts before `99-`. Windows inserts global directives *before* the first `Match` block (a global line after a `Match` is scoped to it) and writes the file BOM-free (a BOM breaks sshd parsing).

## Ubuntu privilege / target-user model

`install-ubuntu.sh` distinguishes **root-level work** from **user-scoped work**:

- `run_root` runs system changes (`apt`, writing `/etc/...`) — prefixed with `sudo` unless already root.
- `TARGET_USER` is the human the environment is being built for: `${SUDO_USER:-$(id -un)}` — i.e. the user who invoked `sudo`, not root. User-scoped installs (Claude/Codex into `~/.local/bin`, dotfiles, npm prefix) go to that user's home.
- `run_target_user` executes a command *as* `TARGET_USER` with the right `HOME`/`PATH`, using `runuser` (preferred, when root) or `sudo -u`. This is why the AI CLIs land in the target user's home even when the script runs under sudo.

This matters because Claude Code refuses `--dangerously-skip-permissions` under root: the tooling is installed for a normal user on purpose. Debian ships `fd`/`bat` as `fdfind`/`batcat`; the script creates user-level `fd`/`bat` shims in `~/.local/bin`.

`install-ubuntu.sh` handles the root case itself via `maybe_bootstrap_user`: when run as root with no non-root `SUDO_USER`, instead of installing for root it creates an unprivileged user (`CLI_USER`, default `dev`) with passwordless sudo, then re-runs *itself* as that user (feeding the script over stdin via `runuser`/`sudo -u`, since a clone in `/root` is unreadable to the new user) and exits. That re-run forces `--no-ssh` so a remote root session can't lock itself out by flipping sshd to 58888/key-only. Running as a normal sudo user skips the bootstrap entirely.

## Shell profiles

Git shortcuts (`gst`, `gd`, `gdca`, `glog`, `glola`, `gsh`, …) are **shell functions/aliases shipped in the profile** (`config/bashrc`, `config/Microsoft.PowerShell_profile.ps1`) — they are intentionally *not* written to `~/.gitconfig`. The bash profile is installed to `~/.bashrc.d/cli-setup.bash` and sourced via an idempotent block appended to `~/.bashrc`. Existing target files are backed up to `*.bak-<timestamp>` before overwrite.

Nerd Fonts are **never installed on the server** — icon glyphs are rendered by the *client* terminal, so fonts belong on the client (README documents client setup).
