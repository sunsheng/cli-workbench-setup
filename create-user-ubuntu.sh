#!/usr/bin/env bash
set -Eeuo pipefail

# One-shot for the "I only have root" case: create a normal user with
# passwordless sudo, then install the whole CLI environment (tools + Claude
# Code / Codex + bash/vim config) under that user. Needed because
# `claude --dangerously-skip-permissions` refuses to run as root.
#
#   bash ./create-user-ubuntu.sh          # creates user "dev"
#   bash ./create-user-ubuntu.sh myname   # creates user "myname"
#
# Safe to re-run: an existing user is reused; sudo + install are reapplied.

NEW_USER="${1:-dev}"
REPO_RAW_BASE="https://raw.githubusercontent.com/sunsheng/windows-cli-setup/main"

step() { printf '\033[36m==> %s\033[0m\n' "$*"; }
skip() { printf '    (skip) %s\n' "$*"; }
die() { printf '\033[31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }
command_exists() { command -v "$1" >/dev/null 2>&1; }

case "$NEW_USER" in
    -h|--help)
        printf 'Usage: bash ./create-user-ubuntu.sh [username]   (default: dev)\n'
        exit 0 ;;
esac

[[ "$NEW_USER" =~ ^[a-z_][a-z0-9_-]*$ ]] ||
    die "Invalid username '$NEW_USER' (use lowercase letters, digits, '-' or '_')."

if [[ -r /etc/os-release ]]; then
    # shellcheck source=/dev/null
    . /etc/os-release
    [[ "${ID:-}" == "ubuntu" ]] || die "This script targets Ubuntu Server; detected ID=${ID:-unknown}."
else
    die "Cannot detect OS: /etc/os-release is missing."
fi

if [[ "$(id -u)" -eq 0 ]]; then
    SUDO=()
else
    command_exists sudo || die "Run as root, or install sudo."
    sudo -v
    SUDO=(sudo)
fi
run_root() { "${SUDO[@]}" "$@"; }

# --- Create the user --------------------------------------------------------
if id "$NEW_USER" >/dev/null 2>&1; then
    skip "User '$NEW_USER' already exists."
else
    step "Creating user '$NEW_USER'..."
    run_root adduser --disabled-password --gecos "" "$NEW_USER"
fi

NEW_HOME="$(getent passwd "$NEW_USER" | cut -d: -f6)"
[[ -n "$NEW_HOME" && -d "$NEW_HOME" ]] || die "Cannot resolve home directory for '$NEW_USER'."

# --- Passwordless sudo ------------------------------------------------------
step "Granting passwordless sudo to '$NEW_USER'..."
run_root usermod -aG sudo "$NEW_USER"
# sudo ignores drop-in files whose names contain '.'; the username regex forbids
# dots, so "90-<user>-nopasswd" is always a valid filename.
SUDOERS_FILE="/etc/sudoers.d/90-$NEW_USER-nopasswd"
SUDOERS_TMP="$(mktemp)"
printf '%s ALL=(ALL) NOPASSWD:ALL\n' "$NEW_USER" > "$SUDOERS_TMP"
run_root visudo -cf "$SUDOERS_TMP" >/dev/null || { rm -f "$SUDOERS_TMP"; die "sudoers syntax check failed."; }
run_root install -m 0440 -o root -g root "$SUDOERS_TMP" "$SUDOERS_FILE"
rm -f "$SUDOERS_TMP"
# Validate just our installed file — not the whole sudoers (a foreign drop-in
# with sloppy perms, e.g. CI runners' /etc/sudoers.d/runner, would fail visudo -c
# through no fault of ours).
run_root visudo -cf "$SUDOERS_FILE" >/dev/null || die "visudo check failed for $SUDOERS_FILE."

# --- Install the environment as the new user --------------------------------
# Locate a bundled install-ubuntu.sh next to this script (clone), else fetch it.
INSTALLER="" FETCHED=0
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
    if [[ -n "$SCRIPT_DIR" && -f "$SCRIPT_DIR/install-ubuntu.sh" ]]; then
        INSTALLER="$SCRIPT_DIR/install-ubuntu.sh"
    fi
fi
if [[ -z "$INSTALLER" ]]; then
    command_exists curl || die "curl is required to fetch install-ubuntu.sh."
    INSTALLER="$(mktemp)"
    FETCHED=1
    curl -fsSL "$REPO_RAW_BASE/install-ubuntu.sh" -o "$INSTALLER"
fi

# Run as the new user. The installer is fed via stdin (bash -s) rather than by
# path: a clone often lives somewhere the new user can't traverse (e.g. /root,
# mode 0700, or another user's home), so `bash <path>` as the new user would hit
# "Permission denied". With stdin, our (root) shell opens the file and the new
# user just inherits the fd.
#
# --no-ssh is hardcoded on purpose: this runs over a remote root session, and
# silently switching sshd to 58888 / key-only could lock you out. Run
# install-ubuntu.sh yourself later if you want SSH hardening.
step "Installing CLI environment as '$NEW_USER' (this also installs claude / codex)..."
RC=0
if [[ "$(id -u)" -eq 0 ]] && command_exists runuser; then
    runuser -u "$NEW_USER" -- env -u SUDO_USER HOME="$NEW_HOME" bash -s -- --no-ssh < "$INSTALLER" || RC=$?
else
    # SC2024: the redirect is intentionally opened by *our* shell (which can read
    # $INSTALLER), not by the dropped-privilege user — that is the whole point here.
    # shellcheck disable=SC2024
    sudo -u "$NEW_USER" -H env -u SUDO_USER bash -s -- --no-ssh < "$INSTALLER" || RC=$?
fi
if ((FETCHED)); then
    rm -f "$INSTALLER"
fi
((RC == 0)) || die "install-ubuntu.sh failed (exit $RC)."

printf '\n'
step "Done!"
cat <<EOF
User '$NEW_USER' is ready with passwordless sudo, and claude / codex are installed.

  Switch to it:  sudo -iu $NEW_USER
  Then run:      claude --dangerously-skip-permissions
EOF
