#!/usr/bin/env bash
set -Eeuo pipefail

NO_PROFILE=0
NO_SSH=0
NODE_MAJOR="${NODE_MAJOR:-24}"
CLI_USER="${CLI_USER:-dev}"           # unprivileged user to create + install for
CLI_PASSWORD="${CLI_PASSWORD:-}"      # console login password; empty => auto-generate
REPO_RAW_BASE="https://raw.githubusercontent.com/sunsheng/cli-workbench-setup/main"
SSH_PORTS=(58888)   # listen on 58888 only; port 22 dropped to dodge SSH brute-force
APT_UPDATED=0
PASSWORD_SET=0        # set to 1 by setup_target_user when it assigns a password
PASSWORD_GENERATED=0  # set to 1 when that password was randomly generated

usage() {
    cat <<'EOF'
Usage: bash ./install-ubuntu.sh [--no-profile] [--no-ssh]

One-shot setup for a modern Ubuntu Server command-line environment.

Must be run as root (whoami must be root). In a single pass it creates an
unprivileged user (claude refuses to run as root), gives it passwordless sudo and
a console login password, prepares an empty ~/.ssh/authorized_keys, and installs
the whole environment for that user. There is no self-bootstrap / re-exec.

Options:
  --no-profile   Install tools only; do not change shell/Vim profiles.
  --no-ssh       Skip OpenSSH Server installation and configuration.
  -h, --help     Show this help.

Environment:
  NODE_MAJOR     Node.js major version to install when node is missing or old.
                 Defaults to 24.
  CLI_USER       Unprivileged user to create and install for. Defaults to dev.
  CLI_PASSWORD   Console login password assigned to CLI_USER on first run (only
                 when the account has no password yet). If unset, a random
                 password is generated and printed once at the end.
EOF
}

step() { printf '\033[36m==> %s\033[0m\n' "$*"; }
skip() { printf '    (skip) %s\n' "$*"; }
warn() { printf '\033[33mWARNING: %s\033[0m\n' "$*" >&2; }
die() { printf '\033[31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }
command_exists() { command -v "$1" >/dev/null 2>&1; }

# Print a ~20-char alphanumeric password. Prefers openssl; falls back to reading a
# fixed chunk of /dev/urandom (read a finite amount up front so no stage in the
# pipe is SIGPIPE'd, which would otherwise trip pipefail).
generate_password() {
    if command_exists openssl; then
        openssl rand -base64 24 | LC_ALL=C tr -dc 'A-Za-z0-9' | cut -c1-20
    else
        head -c 400 /dev/urandom | LC_ALL=C tr -dc 'A-Za-z0-9' | cut -c1-20
    fi
}

while (($#)); do
    case "$1" in
        --no-profile) NO_PROFILE=1 ;;
        --no-ssh) NO_SSH=1 ;;
        -h|--help) usage; exit 0 ;;
        *) die "Unknown option: $1" ;;
    esac
    shift
done

if [[ ! "$NODE_MAJOR" =~ ^[0-9]+$ ]]; then
    die "NODE_MAJOR must be numeric."
fi

if [[ -r /etc/os-release ]]; then
    # shellcheck source=/dev/null
    . /etc/os-release
    if [[ "${ID:-}" != "ubuntu" ]]; then
        die "This installer targets Ubuntu Server; detected ID=${ID:-unknown}."
    fi
    # eza (and a clean apt-only path) requires Ubuntu 24.04+ (noble), where eza
    # first ships in the universe repo. Fail clearly on older releases.
    ubuntu_major="${VERSION_ID:-0}"; ubuntu_major="${ubuntu_major%%.*}"
    if [[ ! "$ubuntu_major" =~ ^[0-9]+$ ]] || ((ubuntu_major < 24)); then
        die "This installer targets Ubuntu 24.04+; detected VERSION_ID=${VERSION_ID:-unknown}."
    fi
else
    die "Cannot detect OS: /etc/os-release is missing."
fi

if ! command_exists apt-get; then
    die "apt-get is required."
fi

# Must run as root: whoami has to be root, anything else stops here. There is no
# self-bootstrap / re-exec — root creates the target user and installs for them
# in one pass.
if [[ "$(id -u)" -ne 0 ]]; then
    die "Must be run as root (whoami=$(whoami)). Re-run with: sudo -i   (or as root)."
fi

[[ "$CLI_USER" =~ ^[a-z_][a-z0-9_-]*$ ]] ||
    die "Invalid CLI_USER '$CLI_USER' (use lowercase letters, digits, '-' or '_')."

# The install target is always the unprivileged CLI_USER. TARGET_HOME/_GROUP and
# USER_BIN are filled in by setup_target_user once the account exists.
TARGET_USER="$CLI_USER"
TARGET_HOME=""
TARGET_GROUP=""
USER_BIN=""

SCRIPT_DIR=""
SCRIPT_SOURCE="${BASH_SOURCE[0]:-}"
if [[ -n "$SCRIPT_SOURCE" ]]; then
    if [[ "$SCRIPT_SOURCE" != /* ]]; then
        SCRIPT_SOURCE="$PWD/$SCRIPT_SOURCE"
    fi
    if SCRIPT_DIR="$(cd -P -- "$(dirname -- "$SCRIPT_SOURCE")" >/dev/null 2>&1 && pwd -P)"; then
        :
    else
        SCRIPT_DIR=""
    fi
    if [[ ! -f "$SCRIPT_DIR/profiles/ubuntu-bashrc" ]]; then
        SCRIPT_DIR=""
    fi
fi

# The script always runs as root; runuser (util-linux, always present) drops to
# the target user with the right HOME/PATH for user-scoped installs.
run_target_user() {
    runuser -u "$TARGET_USER" -- env HOME="$TARGET_HOME" PATH="$USER_BIN:$PATH" "$@"
}

# Create (or reuse) the unprivileged CLI_USER and prepare it as the install
# target. `claude --dangerously-skip-permissions` refuses to run as root, so the
# whole environment is built for this normal user (everything user-scoped goes
# through run_target_user). The account gets:
#   - passwordless sudo,
#   - a login password, so you can still sign in on the VNC / cloud serial console
#     after SSH is locked to key-only on 58888 (a console has no SSH key), and
#   - an empty ~/.ssh/authorized_keys (0700 dir, 0600 file) ready for your key.
# This runs in-process (no re-exec); it just fills in TARGET_HOME/_GROUP/USER_BIN.
setup_target_user() {
    step "Setting up unprivileged user '$CLI_USER' (claude cannot run as root)..."
    if id "$CLI_USER" >/dev/null 2>&1; then
        skip "User '$CLI_USER' already exists."
    else
        adduser --disabled-password --gecos "" "$CLI_USER"
    fi
    usermod -aG sudo "$CLI_USER"

    # sudo ignores drop-in files whose names contain '.'; the username regex
    # forbids dots, so "90-<user>-nopasswd" is always a valid filename.
    local sudoers="/etc/sudoers.d/90-$CLI_USER-nopasswd" tmp
    tmp="$(mktemp)"
    printf '%s ALL=(ALL) NOPASSWD:ALL\n' "$CLI_USER" > "$tmp"
    visudo -cf "$tmp" >/dev/null || { rm -f "$tmp"; die "sudoers syntax check failed."; }
    install -m 0440 -o root -g root "$tmp" "$sudoers"
    rm -f "$tmp"
    visudo -cf "$sudoers" >/dev/null || die "visudo check failed for $sudoers."

    TARGET_HOME="$(getent passwd "$CLI_USER" | cut -d: -f6)"
    TARGET_GROUP="$(id -gn "$CLI_USER")"
    USER_BIN="$TARGET_HOME/.local/bin"
    [[ -n "$TARGET_HOME" && -d "$TARGET_HOME" ]] ||
        die "Cannot resolve home directory for '$CLI_USER'."

    # Give the account a console login password. Only set one when it currently
    # has none (passwd -S status != P): adduser --disabled-password leaves it
    # locked ("L"), but a re-run must never clobber a password you have changed.
    # When CLI_PASSWORD is unset, generate a random one and surface it at the end.
    local pwstatus
    pwstatus="$(passwd -S "$CLI_USER" 2>/dev/null | awk '{print $2}')"
    if [[ "$pwstatus" != "P" ]]; then
        if [[ -z "$CLI_PASSWORD" ]]; then
            CLI_PASSWORD="$(generate_password)"
            [[ -n "$CLI_PASSWORD" ]] || die "Failed to generate a console password."
            PASSWORD_GENERATED=1
        fi
        printf '%s:%s\n' "$CLI_USER" "$CLI_PASSWORD" | chpasswd
        PASSWORD_SET=1
        printf '    Set console login password for %s (printed in the summary below).\n' "$CLI_USER"
    else
        skip "User '$CLI_USER' already has a login password."
    fi

    # Prepare an empty ~/.ssh/authorized_keys with correct ownership/permissions
    # so you can paste a public key in to enable key-only SSH on 58888.
    local ssh_dir="$TARGET_HOME/.ssh" auth_keys="$TARGET_HOME/.ssh/authorized_keys"
    install -d -m 0700 -o "$CLI_USER" -g "$TARGET_GROUP" "$ssh_dir"
    if [[ -e "$auth_keys" ]]; then
        chown "$CLI_USER:$TARGET_GROUP" "$auth_keys"
        chmod 0600 "$auth_keys"
        skip "authorized_keys already exists for '$CLI_USER'."
    else
        install -m 0600 -o "$CLI_USER" -g "$TARGET_GROUP" /dev/null "$auth_keys"
        printf '    Created empty %s (add your public key here).\n' "$auth_keys"
    fi
}

apt_update_once() {
    if [[ "$APT_UPDATED" -eq 0 ]]; then
        step "Updating apt metadata..."
        env DEBIAN_FRONTEND=noninteractive apt-get update
        APT_UPDATED=1
    fi
}

apt_install() {
    apt_update_once
    env DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"
}

enable_universe() {
    step "Ensuring Ubuntu universe repository..."
    # Cloud Ubuntu images already enable universe; only touch apt sources (and
    # pull software-properties-common) when it is genuinely missing. Skipping
    # here avoids an extra apt update and an unnecessary package install.
    #
    # Look only at *active* entries: one-line `deb`/`deb-src` lines and deb822
    # `Components:` lines (leading '#' excluded), then test for `universe` as a
    # whitespace/comma-delimited token. Done without a `grep -q` pipe so a
    # SIGPIPE on the upstream grep can't trip `set -o pipefail`.
    local active_sources
    active_sources="$(grep -RhsE '^[[:space:]]*(deb[[:space:]]|deb-src[[:space:]]|Components:)' \
        /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null || true)"
    if [[ " ${active_sources//[$'\t\n,']/ } " == *" universe "* ]]; then
        skip "universe repository already enabled."
        return
    fi
    if ! command_exists add-apt-repository; then
        apt_install software-properties-common
    fi
    add-apt-repository -y universe
    APT_UPDATED=0
}

resolve_profile_file() {
    local relative_path="$1"
    local local_path=""
    if [[ -n "$SCRIPT_DIR" ]]; then
        local_path="$SCRIPT_DIR/$relative_path"
        if [[ -f "$local_path" ]]; then
            printf '%s\n' "$local_path"
            return 0
        fi
    fi

    command_exists curl || die "curl is required to fetch bundled profile."
    local tmp
    tmp="$(mktemp)"
    if curl -fsSL "$REPO_RAW_BASE/$relative_path" -o "$tmp"; then
        printf '%s\n' "$tmp"
        return 0
    fi
    rm -f "$tmp"
    return 1
}

chown_target() {
    chown "$TARGET_USER:$TARGET_GROUP" "$@"
}

chown_target_link() {
    chown -h "$TARGET_USER:$TARGET_GROUP" "$@"
}

target_mkdir() {
    mkdir -p "$1"
    chown_target "$1"
}

install_user_file() {
    local src="$1"
    local dst="$2"
    local dst_dir
    dst_dir="$(dirname -- "$dst")"
    target_mkdir "$dst_dir"
    if [[ -e "$dst" ]]; then
        local backup
        backup="$dst.bak-$(date +%Y%m%d-%H%M%S)"
        cp -a "$dst" "$backup"
        chown_target "$backup"
        printf '    Existing file backed up to %s\n' "$backup"
    fi
    install -m 0644 "$src" "$dst"
    chown_target "$dst"
}

ensure_bashrc_source() {
    local bashrc="$TARGET_HOME/.bashrc"
    local begin="# >>> cli-setup >>>"
    local end="# <<< cli-setup <<<"
    local source_line="[ -r \"\$HOME/.bashrc.d/cli-setup.bash\" ] && . \"\$HOME/.bashrc.d/cli-setup.bash\""

    if [[ -f "$bashrc" ]] && grep -Fq "$begin" "$bashrc"; then
        skip ".bashrc already sources cli-setup."
        return
    fi

    {
        printf '\n%s\n' "$begin"
        printf '%s\n' "$source_line"
        printf '%s\n' "$end"
    } >> "$bashrc"
    chown_target "$bashrc"
    printf '    Added cli-setup source block to %s\n' "$bashrc"
}

set_default_shell() {
    local shell_path="$1"
    local current_shell

    [[ -x "$shell_path" ]] || die "$shell_path is not executable."
    if ! grep -Fxq "$shell_path" /etc/shells; then
        printf '%s\n' "$shell_path" >> /etc/shells
    fi

    current_shell="$(getent passwd "$TARGET_USER" | cut -d: -f7)"
    if [[ "$current_shell" == "$shell_path" ]]; then
        skip "Default shell already set to $shell_path."
        return
    fi

    usermod -s "$shell_path" "$TARGET_USER"
    printf '    Set default shell for %s to %s\n' "$TARGET_USER" "$shell_path"
}

ensure_user_bin_links() {
    step "Ensuring Debian command-name shims..."
    target_mkdir "$USER_BIN"

    if ! command_exists fd && command_exists fdfind && [[ ! -e "$USER_BIN/fd" ]]; then
        ln -s "$(command -v fdfind)" "$USER_BIN/fd"
        chown_target_link "$USER_BIN/fd"
        printf '    Linked fd -> fdfind in %s\n' "$USER_BIN"
    elif command_exists fd || [[ -e "$USER_BIN/fd" ]]; then
        skip "fd already available."
    fi

    if ! command_exists bat && command_exists batcat && [[ ! -e "$USER_BIN/bat" ]]; then
        ln -s "$(command -v batcat)" "$USER_BIN/bat"
        chown_target_link "$USER_BIN/bat"
        printf '    Linked bat -> batcat in %s\n' "$USER_BIN"
    elif command_exists bat || [[ -e "$USER_BIN/bat" ]]; then
        skip "bat already available."
    fi

    export PATH="$USER_BIN:$PATH"
}

ensure_npm_user_prefix() {
    command_exists npm || die "npm is required for AI CLI npm fallback."
    target_mkdir "$TARGET_HOME/.local"
    local prefix=""
    prefix="$(run_target_user npm config get prefix 2>/dev/null || true)"
    if [[ -z "$prefix" || "$prefix" == /usr || "$prefix" == /usr/* || ! -w "$prefix" ]]; then
        run_target_user npm config set prefix "$TARGET_HOME/.local"
    fi
    export PATH="$USER_BIN:$PATH"
}

node_major_version() {
    node -p "Number(process.versions.node.split('.')[0])" 2>/dev/null || true
}

setup_nodesource() {
    step "Configuring NodeSource Node.js ${NODE_MAJOR}.x repository..."
    apt_install ca-certificates curl gnupg
    install -d -m 0755 /etc/apt/keyrings

    local tmp_dir tmp_key tmp_gpg
    tmp_dir="$(mktemp -d)"
    tmp_key="$tmp_dir/nodesource.key"
    tmp_gpg="$tmp_dir/nodesource.gpg"
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key -o "$tmp_key"
    gpg --dearmor -o "$tmp_gpg" "$tmp_key"
    install -m 0644 "$tmp_gpg" /etc/apt/keyrings/nodesource.gpg
    printf 'deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_%s.x nodistro main\n' "$NODE_MAJOR" |
        tee /etc/apt/sources.list.d/nodesource.list >/dev/null
    rm -rf "$tmp_dir"
    APT_UPDATED=0
}

install_nodejs() {
    step "Ensuring Node.js ${NODE_MAJOR}.x LTS..."
    local current_major=""
    if command_exists node; then
        current_major="$(node_major_version)"
    fi
    if command_exists node && command_exists npm && command_exists npx &&
        [[ "$current_major" =~ ^[0-9]+$ && "$current_major" -ge "$NODE_MAJOR" ]]; then
        skip "node $(node --version), npm, and npx already available."
        return
    fi

    setup_nodesource
    apt_install nodejs
}

install_codex_cli() {
    step "Ensuring Codex CLI..."
    export PATH="$USER_BIN:$PATH"
    if command_exists codex; then
        skip "codex already installed."
        return
    fi

    # shellcheck disable=SC2016
    if run_target_user sh -lc 'set -e; tmp="$(mktemp)"; trap "rm -f \"$tmp\"" EXIT; curl -fsSL https://chatgpt.com/codex/install.sh -o "$tmp"; CODEX_NON_INTERACTIVE=1 CODEX_INSTALL_DIR="$HOME/.local/bin" sh "$tmp"'; then
        :
    else
        warn "Codex official installer failed; falling back to npm."
        ensure_npm_user_prefix
        run_target_user npm install -g @openai/codex
    fi

    export PATH="$USER_BIN:$PATH"
    if ! command_exists codex; then
        warn "codex command still not found after official installer; falling back to npm."
        ensure_npm_user_prefix
        run_target_user npm install -g @openai/codex
    fi
    command_exists codex || die "codex was not found after installation."
}

# Download the Claude Code native binary straight from downloads.claude.ai and run
# its built-in installer. The entry script at claude.ai/install.sh sits behind
# Cloudflare's managed challenge, which 403s bare curl from datacenter IPs (cloud
# VMs); the downloads host has no such challenge. Returns non-zero on any failure
# so the caller can fall back to the official installer or npm.
download_claude_native() {
    # shellcheck disable=SC2016
    run_target_user sh -lc '
        set -e
        base="https://downloads.claude.ai/claude-code-releases"
        ver="$(curl -fsSL "$base/latest")"
        case "$ver" in
            [0-9]*.[0-9]*.[0-9]*) : ;;
            *) echo "Unexpected version from downloads.claude.ai: $ver" >&2; exit 1 ;;
        esac
        case "$(uname -m)" in
            x86_64|amd64) arch="x64" ;;
            aarch64|arm64) arch="arm64" ;;
            *) echo "Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
        esac
        if [ -f /lib/libc.musl-x86_64.so.1 ] || [ -f /lib/libc.musl-aarch64.so.1 ]; then
            platform="linux-${arch}-musl"
        else
            platform="linux-${arch}"
        fi
        manifest="$(curl -fsSL "$base/$ver/manifest.json")"
        expected="$(printf "%s" "$manifest" | jq -r ".platforms[\"$platform\"].checksum // empty")"
        binary="$(printf "%s" "$manifest" | jq -r ".platforms[\"$platform\"].binary // \"claude\"")"
        if [ -z "$expected" ]; then
            echo "Platform $platform not found in manifest" >&2
            exit 1
        fi
        tmp="$(mktemp)"
        trap "rm -f \"$tmp\"" EXIT
        curl -fsSL -o "$tmp" "$base/$ver/$platform/$binary"
        actual="$(sha256sum "$tmp" | cut -d" " -f1)"
        if [ "$expected" != "$actual" ]; then
            echo "Checksum verification failed for $platform" >&2
            exit 1
        fi
        chmod +x "$tmp"
        "$tmp" install
    '
}

install_claude_code_cli() {
    step "Ensuring Claude Code CLI..."
    export PATH="$USER_BIN:$PATH"
    if command_exists claude; then
        skip "claude already installed."
        return
    fi

    # Preferred: native binary direct from downloads.claude.ai (works from datacenter
    # IPs). Fallback 1: claude.ai/install.sh (works from residential IPs / via proxy).
    # Fallback 2: npm.
    # shellcheck disable=SC2016
    if download_claude_native; then
        :
    elif run_target_user sh -lc 'set -e; tmp="$(mktemp)"; trap "rm -f \"$tmp\"" EXIT; curl -fsSL https://claude.ai/install.sh -o "$tmp"; bash "$tmp"'; then
        :
    else
        warn "Claude Code native and official installers failed; falling back to npm."
        ensure_npm_user_prefix
        run_target_user npm install -g @anthropic-ai/claude-code
    fi

    export PATH="$USER_BIN:$PATH"
    if ! command_exists claude; then
        warn "claude command still not found after installers; falling back to npm."
        ensure_npm_user_prefix
        run_target_user npm install -g @anthropic-ai/claude-code
    fi
    command_exists claude || die "claude was not found after installation."
}

ensure_locale_line() {
    local loc="$1"
    local line="$loc UTF-8"
    local escaped="${loc//./\\.}"
    if grep -Fxq "$line" /etc/locale.gen 2>/dev/null; then
        return
    fi
    if grep -Eq "^#[[:space:]]*${escaped} UTF-8([[:space:]]|$)" /etc/locale.gen 2>/dev/null; then
        sed -ri "s|^#[[:space:]]*(${escaped} UTF-8)|\1|" /etc/locale.gen
    else
        printf '%s\n' "$line" | tee -a /etc/locale.gen >/dev/null
    fi
}

# Generate the en_US.UTF-8 locale and make it the system default so a bare
# server stops sitting on C/POSIX (which makes SSH clients print
# "setlocale: cannot change locale").
configure_locale() {
    step "Ensuring en_US.UTF-8 locale..."
    apt_install locales

    ensure_locale_line en_US.UTF-8
    locale-gen

    # Give the system a stable default when none is configured (a bare server
    # otherwise sits on C/POSIX). Never override an existing LANG.
    if [[ ! -s /etc/default/locale ]] || ! grep -q '^LANG=' /etc/default/locale 2>/dev/null; then
        update-locale LANG=en_US.UTF-8
    fi
}

install_tools() {
    step "Installing CLI tools..."
    enable_universe
    apt_update_once

    local packages=(
        bat
        ca-certificates
        curl
        eza
        fd-find
        fzf
        gh
        git
        gnupg
        jq
        p7zip-full
        ripgrep
        unzip
        vim
        zsh
        zoxide
    )

    if [[ "$NO_SSH" -eq 0 ]]; then
        packages+=(openssh-server)
    fi

    apt_install "${packages[@]}"

    install_nodejs
    ensure_user_bin_links
    install_codex_cli
    install_claude_code_cli
}

install_profile() {
    if [[ "$NO_PROFILE" -eq 1 ]]; then
        skip "Profile install skipped (--no-profile)."
        return
    fi

    step "Installing shell profiles..."
    local bash_src
    if ! bash_src="$(resolve_profile_file "profiles/ubuntu-bashrc")"; then
        warn "Could not obtain profiles/ubuntu-bashrc; skipping bash profile."
    else
        install_user_file "$bash_src" "$TARGET_HOME/.bashrc.d/cli-setup.bash"
        ensure_bashrc_source
    fi

    local zprofile_src zshrc_src
    if ! zprofile_src="$(resolve_profile_file "profiles/ubuntu-zprofile")"; then
        warn "Could not obtain profiles/ubuntu-zprofile; skipping zprofile."
    else
        install_user_file "$zprofile_src" "$TARGET_HOME/.zprofile"
    fi

    if ! zshrc_src="$(resolve_profile_file "profiles/ubuntu-zshrc")"; then
        warn "Could not obtain profiles/ubuntu-zshrc; skipping zshrc."
    else
        install_user_file "$zshrc_src" "$TARGET_HOME/.zshrc"
    fi

    set_default_shell /usr/bin/zsh

    step "Installing Vim profile..."
    local vim_src
    if ! vim_src="$(resolve_profile_file "profiles/ubuntu-vimrc")"; then
        warn "Could not obtain profiles/ubuntu-vimrc; skipping vim config."
        return
    fi
    target_mkdir "$TARGET_HOME/.vim/undo"
    install_user_file "$vim_src" "$TARGET_HOME/.vimrc"
}

restart_ssh_service() {
    local sshd_bin=""
    sshd_bin="$(command -v sshd || true)"
    if [[ -z "$sshd_bin" && -x /usr/sbin/sshd ]]; then
        sshd_bin="/usr/sbin/sshd"
    fi
    if [[ -n "$sshd_bin" ]]; then
        "$sshd_bin" -t
    fi

    systemctl enable --now ssh
    systemctl restart ssh
}

configure_ssh() {
    if [[ "$NO_SSH" -eq 1 ]]; then
        skip "OpenSSH Server setup skipped (--no-ssh)."
        return
    fi

    step "Configuring OpenSSH Server..."
    groupadd -f ssh-users
    usermod -aG ssh-users "$TARGET_USER"

    local conf="/etc/ssh/sshd_config.d/99-cli-setup.conf"
    local tmp
    tmp="$(mktemp)"
    {
        printf '# Managed by install-ubuntu.sh\n'
        for port in "${SSH_PORTS[@]}"; do
            printf 'Port %s\n' "$port"
        done
        printf 'AllowGroups sudo ssh-users\n'
        printf 'PasswordAuthentication no\n'
    } > "$tmp"
    install -m 0644 "$tmp" "$conf"
    rm -f "$tmp"

    # Cloud images often ship /etc/ssh/sshd_config.d/50-cloud-init.conf with
    # `PasswordAuthentication yes`. sshd honours the *first* match, and 50-
    # sorts before our 99-, so the `no` above would be ignored. Comment out any
    # active PasswordAuthentication yes in earlier drop-ins so key-only wins.
    local dropin
    for dropin in /etc/ssh/sshd_config.d/*.conf; do
        [[ -e "$dropin" ]] || continue
        [[ "$dropin" == "$conf" ]] && continue
        if grep -Eq '^[[:space:]]*PasswordAuthentication[[:space:]]+yes' "$dropin"; then
            sed -ri 's/^([[:space:]]*PasswordAuthentication[[:space:]]+yes.*)$/# \1  # disabled by install-ubuntu.sh/' "$dropin"
        fi
    done

    if command_exists ufw; then
        for port in "${SSH_PORTS[@]}"; do
            ufw allow "$port/tcp"
        done
    else
        skip "ufw not installed; firewall rules were not changed."
    fi

    restart_ssh_service
}

setup_target_user
configure_locale
install_tools
install_profile
configure_ssh

printf '\n'
step "Done! Environment installed for user '$CLI_USER'."
if [[ "$PASSWORD_SET" -eq 1 && "$PASSWORD_GENERATED" -eq 1 ]]; then
    printf '  Console (VNC/serial) login:  %s / %s   <-- RANDOM, save it now (change: passwd)\n' "$CLI_USER" "$CLI_PASSWORD"
elif [[ "$PASSWORD_SET" -eq 1 ]]; then
    printf '  Console (VNC/serial) login:  %s / %s   (change it: passwd)\n' "$CLI_USER" "$CLI_PASSWORD"
else
    printf '  Console (VNC/serial) login:  %s / <existing password unchanged>\n' "$CLI_USER"
fi
printf '  Enable SSH: add your public key to %s/.ssh/authorized_keys, then: ssh -p %s %s@<host>\n' \
    "$TARGET_HOME" "${SSH_PORTS[0]}" "$CLI_USER"
printf '  Become the user:  sudo -iu %s   then run:  claude --dangerously-skip-permissions\n' "$CLI_USER"
