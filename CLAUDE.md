# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Two parallel one-shot installers that provision the *same* modern CLI environment on two OSes:

- `install-windows.ps1` — Windows Server / Windows, via [Scoop](https://scoop.sh).
- `add-windows-admin-ssh-key.ps1` — Windows helper that appends a public key to `%ProgramData%\ssh\administrators_authorized_keys` and fixes its ACL.
- `install-ubuntu.sh` — Ubuntu Server, via `apt`.

They are deliberate mirrors: the same tool set (git, gh, ripgrep, fd, bat, fzf, jq, 7zip, eza, vim, zoxide, Node.js LTS, Codex CLI, Claude Code CLI), the same idempotent step structure, the same AI-CLI install strategy, and a parallel SSH hardening posture (they diverge on password auth — see below). Windows additionally installs **PowerShell 7 (pwsh)** + the **PSFzf** module and points its SSH default shell at pwsh; Ubuntu installs **zsh** as the default login shell. **When you change behavior on one side, check whether the other side needs the mirror change** (and update `README.md`, which documents both). `profiles/` holds the shipped shell and Vim profiles consumed by both (`ubuntu-zprofile`, `ubuntu-zshrc`, `ubuntu-bashrc`, `powershell-profile.ps1`, `ubuntu-vimrc`, `windows-vimrc`).

`README.md` is the user-facing doc and is written in Chinese — keep it in sync with any behavior change.

## Commands

There is no build and no unit-test framework. Validation = lint + a real install-and-verify, mirrored in `.github/workflows/ci.yml`.

Lint (run before pushing):

```bash
# Bash/zsh side
bash -n install-ubuntu.sh profiles/ubuntu-bashrc
zsh -n profiles/ubuntu-zprofile
zsh -n profiles/ubuntu-zshrc
shellcheck -s bash install-ubuntu.sh profiles/ubuntu-bashrc
```

```powershell
# PowerShell side: parse, then analyze (Error severity gates CI)
[System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path install-windows.ps1), [ref]$null, [ref]([ref]$null).Value)
[System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path add-windows-admin-ssh-key.ps1), [ref]$null, [ref]([ref]$null).Value)
[System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path profiles/powershell-profile.ps1), [ref]$null, [ref]([ref]$null).Value)
Invoke-ScriptAnalyzer -Path . -Recurse -Severity Error
```

Run an installer locally (both are safe to re-run — every step checks for an existing install first):

```bash
bash ./install-ubuntu.sh                 # full run
bash ./install-ubuntu.sh --no-profile    # tools only, no shell/vim config
bash ./install-ubuntu.sh --no-ssh        # skip OpenSSH config
NODE_MAJOR=22 bash ./install-ubuntu.sh   # pin Node major version
```

```powershell
.\install-windows.ps1            # full run (SSH step auto-skips in a non-admin session)
.\install-windows.ps1 -NoProfile
.\install-windows.ps1 -NoSsh
.\add-windows-admin-ssh-key.ps1 -PublicKeyPath $HOME\.ssh\id_ed25519.pub  # admin session
```

CI (`ubuntu-latest` + `windows-latest`) runs the installer with `--no-ssh` / `-NoSsh`, then asserts every CLI is on `PATH` and that the profile defines the `ll` / git-shortcut functions. If you add a tool or a profile function, add it to the verify lists in `ci.yml`.

## Conventions that span files

**Idempotency is mandatory.** Every step must detect an existing install/config and skip (`command_exists` / `Get-Command` guards, `skip`/`Write-Skip`). Re-running must be a no-op.

**Profile resolution: local-or-fetch.** Both installers can run from a clone *or* piped from `curl`/`iwr`. `resolve_profile_file` (bash) / `Resolve-ProfileFile` (ps1) return the on-disk `profiles/<file>` when the script dir is known, otherwise download it from `REPO_RAW_BASE`/`$RepoRawBase` (the hardcoded `raw.githubusercontent.com/sunsheng/cli-workbench-setup/main`). Keep that base URL correct if the repo moves.

**AI CLI install is a deliberate 3-tier fallback** (`install_claude_code_cli` / `Install-ClaudeCodeCli`, and the Codex equivalents):
1. Native binary pulled *directly* from `downloads.claude.ai` (resolve `latest` → download platform binary → verify SHA256 from `manifest.json` → run the binary's built-in `install`).
2. Official entry script (`claude.ai/install.*`).
3. `npm install -g`.
The native-first ordering is not arbitrary: `claude.ai/install.*` sits behind a Cloudflare managed challenge that **403s bare requests from datacenter/cloud IPs**, while `downloads.claude.ai` does not. Preserve this ordering and the checksum verification if you touch the installer.

**SSH hardening posture.** Both listen on port **58888 only** (22 intentionally dropped to dodge internet-wide brute force), restrict logins to a group allowlist, and **disable direct root login**. **Password auth differs by OS:** Windows is **key-only** (`PasswordAuthentication no`); **Ubuntu allows password login** (`PasswordAuthentication yes`) in addition to keys. Ubuntu writes `/etc/ssh/sshd_config.d/99-cli-setup.conf` (`Port`, `AllowGroups sudo ssh-users`, `PermitRootLogin no`, `PasswordAuthentication yes`) and comments out any conflicting `PasswordAuthentication`/`PermitRootLogin` in earlier drop-ins (e.g. cloud-init's `50-*.conf`) so its values win — sshd honors the *first* match, and `50-` sorts before `99-`. Windows inserts global directives *before* the first `Match` block (a global line after a `Match` is scoped to it) and writes the file BOM-free (a BOM breaks sshd parsing).

## Ubuntu privilege / target-user model

`install-ubuntu.sh` **must run as root** — it checks `id -u` up front and `die`s with the current `whoami` otherwise. There is no self-bootstrap / re-exec; root does everything for the target user in a single pass. It distinguishes **root-level work** from **user-scoped work**:

- Root-level system changes (`apt`, writing `/etc/...`) run directly — the script is always root, so there is no `sudo` indirection.
- `TARGET_USER` is always the unprivileged `CLI_USER` (default `dev`), *not* root. User-scoped installs (Claude/Codex into `~/.local/bin`, dotfiles, npm prefix) go to that user's home.
- `run_target_user` executes a command *as* `TARGET_USER` with the right `HOME`/`PATH` via `runuser` (always present from util-linux). This is why the AI CLIs land in the target user's home even though the script runs as root.

This matters because Claude Code refuses `--dangerously-skip-permissions` under root: the tooling is installed for a normal user on purpose. Debian ships `fd`/`bat` as `fdfind`/`batcat`; the script creates user-level `fd`/`bat` shims in `~/.local/bin`. `eza` is installed from apt (universe) on Ubuntu 24.04+ and from Scoop on Windows.

`setup_target_user` (called first, before any install step) creates/reuses `CLI_USER`, gives it passwordless sudo, and sets up a login that works on both the console and SSH:

- It sets a **login password** via `chpasswd` (used for the VNC/serial console *and* for SSH password login), but **only when the account has none yet** (`passwd -S` status `!= P`) so a re-run never clobbers a password you changed. `CLI_PASSWORD` overrides it; when unset, `generate_password` makes a random 8–10 char one (mixed-case letters + digits, no symbols or look-alike characters; openssl, else `/dev/urandom`). That password is printed in the final summary **and saved to `~/.cli-setup-password` (0600, owned by `CLI_USER`)** so it stays recoverable, not just printed once.
- It creates `~/.ssh` (0700) and an empty `~/.ssh/authorized_keys` (0600), owned by `CLI_USER`, ready for a public key — optional now, since Ubuntu also allows password login.

`configure_ssh` runs in the *same pass* (no forced `--no-ssh`): hardening SSH to 58888 with `PermitRootLogin no` while keeping password auth on is safe because the unprivileged user has a known password (saved on disk and printable), and the VNC/serial console remains as a fallback. The old `maybe_bootstrap_user` re-exec model (re-running the script over stdin as the new user, forcing `--no-ssh`) is gone.

## Shell profiles

Git shortcuts (`gst`, `gd`, `gdca`, `glog`, `glola`, `gsh`, …) are **shell functions/aliases shipped in the profile** (`profiles/ubuntu-zshrc`, `profiles/ubuntu-bashrc`, `profiles/powershell-profile.ps1`) — they are intentionally *not* written to `~/.gitconfig`. Ubuntu installs zsh as the default login shell for `CLI_USER`, writes `~/.zprofile` / `~/.zshrc`, and still installs the bash profile to `~/.bashrc.d/cli-setup.bash` with an idempotent source block appended to `~/.bashrc`. Existing target files are backed up to `*.bak-<timestamp>` before overwrite.

Nerd Fonts are **never installed on the server** — icon glyphs are rendered by the *client* terminal, so fonts belong on the client (README documents client setup).
