#!/usr/bin/env bash
set -Eeuo pipefail

NO_PROFILE=0
NO_SSH=0
NODE_MAJOR="${NODE_MAJOR:-24}"
REPO_RAW_BASE="https://raw.githubusercontent.com/sunsheng/windows-cli-setup/main"
SSH_PORTS=(58888)   # listen on 58888 only; port 22 dropped to dodge SSH brute-force
APT_UPDATED=0

usage() {
    cat <<'EOF'
Usage: bash ./install-ubuntu.sh [--no-profile] [--no-ssh]

One-shot setup for a modern Ubuntu Server command-line environment.

Options:
  --no-profile   Install tools only; do not change bash/vim config.
  --no-ssh       Skip OpenSSH Server installation and configuration.
  -h, --help     Show this help.

Environment:
  NODE_MAJOR     Node.js major version to install when node is missing or old.
                 Defaults to 24.
EOF
}

step() { printf '\033[36m==> %s\033[0m\n' "$*"; }
skip() { printf '    (skip) %s\n' "$*"; }
warn() { printf '\033[33mWARNING: %s\033[0m\n' "$*" >&2; }
die() { printf '\033[31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }
command_exists() { command -v "$1" >/dev/null 2>&1; }

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
else
    die "Cannot detect OS: /etc/os-release is missing."
fi

if ! command_exists apt-get; then
    die "apt-get is required."
fi

if [[ "$(id -u)" -eq 0 ]]; then
    SUDO=()
else
    command_exists sudo || die "sudo is required when not running as root."
    sudo -v
    SUDO=(sudo)
fi

TARGET_USER="${SUDO_USER:-$(id -un)}"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
TARGET_GROUP="$(id -gn "$TARGET_USER")"
USER_BIN="$TARGET_HOME/.local/bin"

if [[ -z "$TARGET_HOME" || ! -d "$TARGET_HOME" ]]; then
    die "Cannot resolve home directory for user '$TARGET_USER'."
fi

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
    if [[ ! -f "$SCRIPT_DIR/config/bashrc" ]]; then
        SCRIPT_DIR=""
    fi
fi

run_root() {
    "${SUDO[@]}" "$@"
}

run_target_user() {
    if [[ "$(id -u)" -eq 0 && "$TARGET_USER" != "root" ]]; then
        if command_exists runuser; then
            runuser -u "$TARGET_USER" -- env HOME="$TARGET_HOME" PATH="$USER_BIN:$PATH" "$@"
        elif command_exists sudo; then
            sudo -u "$TARGET_USER" -H env HOME="$TARGET_HOME" PATH="$USER_BIN:$PATH" "$@"
        else
            die "runuser or sudo is required to install user-scoped CLI tools for '$TARGET_USER'."
        fi
    else
        env HOME="$TARGET_HOME" PATH="$USER_BIN:$PATH" "$@"
    fi
}

apt_update_once() {
    if [[ "$APT_UPDATED" -eq 0 ]]; then
        step "Updating apt metadata..."
        run_root env DEBIAN_FRONTEND=noninteractive apt-get update
        APT_UPDATED=1
    fi
}

apt_install() {
    apt_update_once
    run_root env DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"
}

enable_universe() {
    step "Ensuring Ubuntu universe repository..."
    if ! command_exists add-apt-repository; then
        apt_install software-properties-common
    fi
    run_root add-apt-repository -y universe
    APT_UPDATED=0
}

apt_has_package() {
    apt-cache show "$1" >/dev/null 2>&1
}

resolve_config_file() {
    local relative_path="$1"
    local local_path=""
    if [[ -n "$SCRIPT_DIR" ]]; then
        local_path="$SCRIPT_DIR/$relative_path"
        if [[ -f "$local_path" ]]; then
            printf '%s\n' "$local_path"
            return 0
        fi
    fi

    command_exists curl || die "curl is required to fetch bundled config."
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
    if [[ "$(id -u)" -eq 0 ]]; then
        chown "$TARGET_USER:$TARGET_GROUP" "$@"
    fi
}

chown_target_link() {
    if [[ "$(id -u)" -eq 0 ]]; then
        chown -h "$TARGET_USER:$TARGET_GROUP" "$@"
    fi
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
    run_root install -d -m 0755 /etc/apt/keyrings

    local tmp_dir tmp_key tmp_gpg
    tmp_dir="$(mktemp -d)"
    tmp_key="$tmp_dir/nodesource.key"
    tmp_gpg="$tmp_dir/nodesource.gpg"
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key -o "$tmp_key"
    gpg --dearmor -o "$tmp_gpg" "$tmp_key"
    run_root install -m 0644 "$tmp_gpg" /etc/apt/keyrings/nodesource.gpg
    printf 'deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_%s.x nodistro main\n' "$NODE_MAJOR" |
        run_root tee /etc/apt/sources.list.d/nodesource.list >/dev/null
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

install_eza_release() {
    if command_exists eza; then
        skip "eza already available."
        return
    fi

    local arch asset tmp eza_bin
    arch="$(uname -m)"
    case "$arch" in
        x86_64|amd64) asset="eza_x86_64-unknown-linux-gnu.tar.gz" ;;
        aarch64|arm64) asset="eza_aarch64-unknown-linux-gnu.tar.gz" ;;
        *) die "No eza binary fallback is configured for architecture '$arch'." ;;
    esac

    step "Installing eza from upstream release..."
    tmp="$(mktemp -d)"
    curl -fsSL "https://github.com/eza-community/eza/releases/latest/download/$asset" -o "$tmp/eza.tar.gz"
    tar -xzf "$tmp/eza.tar.gz" -C "$tmp"
    eza_bin="$(find "$tmp" -type f -name eza -perm -u+x -print -quit)"
    if [[ -z "$eza_bin" ]]; then
        rm -rf "$tmp"
        die "Could not find eza binary in release archive."
    fi
    run_root install -m 0755 "$eza_bin" /usr/local/bin/eza
    rm -rf "$tmp"
}

install_tools() {
    step "Installing CLI tools..."
    enable_universe
    apt_update_once

    local packages=(
        build-essential
        bat
        ca-certificates
        curl
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
        zoxide
    )

    if apt_has_package eza; then
        packages+=(eza)
    fi

    if [[ "$NO_SSH" -eq 0 ]]; then
        packages+=(openssh-server)
    fi

    apt_install "${packages[@]}"

    if ! apt_has_package eza; then
        install_eza_release
    fi

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

    step "Installing bash profile..."
    local bash_src
    if ! bash_src="$(resolve_config_file "config/bashrc")"; then
        warn "Could not obtain config/bashrc; skipping bash profile."
    else
        install_user_file "$bash_src" "$TARGET_HOME/.bashrc.d/cli-setup.bash"
        ensure_bashrc_source
    fi

    step "Installing vim config..."
    local vim_src
    if ! vim_src="$(resolve_config_file "config/vimrc")"; then
        warn "Could not obtain config/vimrc; skipping vim config."
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
        run_root "$sshd_bin" -t
    fi

    if command_exists systemctl && [[ -d /run/systemd/system ]]; then
        run_root systemctl enable --now ssh
        run_root systemctl restart ssh
    elif command_exists service; then
        run_root service ssh restart
    else
        warn "No service manager found; ssh config was written but ssh was not restarted."
    fi
}

configure_ssh() {
    if [[ "$NO_SSH" -eq 1 ]]; then
        skip "OpenSSH Server setup skipped (--no-ssh)."
        return
    fi

    step "Configuring OpenSSH Server..."
    run_root groupadd -f ssh-users
    run_root usermod -aG ssh-users "$TARGET_USER"

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
    run_root install -m 0644 "$tmp" "$conf"
    rm -f "$tmp"

    # Cloud images often ship /etc/ssh/sshd_config.d/50-cloud-init.conf with
    # `PasswordAuthentication yes`. sshd honours the *first* match, and 50-
    # sorts before our 99-, so the `no` above would be ignored. Comment out any
    # active PasswordAuthentication yes in earlier drop-ins so key-only wins.
    local dropin
    for dropin in /etc/ssh/sshd_config.d/*.conf; do
        [[ -e "$dropin" ]] || continue
        [[ "$dropin" == "$conf" ]] && continue
        if run_root grep -Eq '^[[:space:]]*PasswordAuthentication[[:space:]]+yes' "$dropin"; then
            run_root sed -ri 's/^([[:space:]]*PasswordAuthentication[[:space:]]+yes.*)$/# \1  # disabled by install-ubuntu.sh/' "$dropin"
        fi
    done

    if command_exists ufw; then
        for port in "${SSH_PORTS[@]}"; do
            run_root ufw allow "$port/tcp"
        done
    else
        skip "ufw not installed; firewall rules were not changed."
    fi

    restart_ssh_service
}

install_tools
install_profile
configure_ssh

printf '\n'
step "Done! Open a new bash session, or run: source ~/.bashrc"
