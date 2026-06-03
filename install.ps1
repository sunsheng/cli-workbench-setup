#requires -Version 5.1
<#
.SYNOPSIS
    One-shot setup for a modern Windows command-line environment.

.DESCRIPTION
    Installs the Scoop package manager, a set of common CLI tools, and the
    PSFzf module, then installs the bundled PowerShell profile that wires up
    aliases (eza/bat) and keybindings (fzf Ctrl+R / Ctrl+T) and zoxide.

    Safe to re-run: every step checks for existing installs before acting.

.EXAMPLE
    # From a normal (non-admin) PowerShell session:
    iwr -useb https://raw.githubusercontent.com/sunsheng/windows-cli-setup/main/install.ps1 | iex

.EXAMPLE
    # Or clone the repo and run locally:
    .\install.ps1
#>
[CmdletBinding()]
param(
    # Skip the personal config (PowerShell profile, _vimrc — git aliases live in the profile).
    [switch]$NoProfile,
    # Skip the OpenSSH Server step (it also requires an elevated session).
    [switch]$NoSsh
)

$ErrorActionPreference = 'Stop'

function Write-Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
function Write-Skip($msg) { Write-Host "    (skip) $msg" -ForegroundColor DarkGray }

# True when the current session is elevated (Administrator).
function Test-Admin {
    ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Base URL for fetching bundled config files when no local copy is available.
$RepoRawBase = 'https://raw.githubusercontent.com/sunsheng/windows-cli-setup/main'

# Resolve a bundled config file to a local path.
#   - Run from a clone (`$PSScriptRoot` set): use the file on disk.
#   - Run via `iwr ... | iex` (`$PSScriptRoot` empty): download it from GitHub.
# Returns $null (with a warning) if the file can't be obtained.
function Resolve-ConfigFile($relativePath) {   # e.g. 'config/_vimrc'
    if ($PSScriptRoot) {
        $local = Join-Path $PSScriptRoot ($relativePath -replace '/', '\')
        if (Test-Path $local) { return $local }
    }
    $url = "$RepoRawBase/$relativePath"
    $tmp = Join-Path $env:TEMP ('wcs-' + (Split-Path $relativePath -Leaf))
    try {
        Write-Host "    Downloading $relativePath from GitHub..." -ForegroundColor DarkGray
        Invoke-RestMethod -Uri $url -OutFile $tmp
        return $tmp
    } catch {
        Write-Warning "Could not fetch $relativePath from $url - skipping."
        return $null
    }
}

# Ensure global sshd_config directives exist, inserted *before* the first Match
# block (a global directive placed after a Match is scoped to that block).
# Skips any line already present verbatim. Returns $true if the file changed.
function Add-SshdGlobalLines($path, [string[]]$lines) {
    if (-not (Test-Path $path)) { return $false }
    $content = @(Get-Content -Path $path)
    $toAdd = @($lines | Where-Object { $content -notcontains $_ })
    if ($toAdd.Count -eq 0) { return $false }
    $idx = -1
    for ($i = 0; $i -lt $content.Count; $i++) {
        if ($content[$i] -match '^\s*Match\b') { $idx = $i; break }
    }
    if ($idx -gt 0) {
        $new = $content[0..($idx - 1)] + $toAdd + $content[$idx..($content.Count - 1)]
    } elseif ($idx -eq 0) {
        $new = $toAdd + $content
    } else {
        $new = $content + $toAdd
    }
    # ASCII keeps the file BOM-free; a BOM on the first line breaks sshd parsing.
    Set-Content -Path $path -Value $new -Encoding ascii
    return $true
}

# --- 1. Install Scoop -------------------------------------------------------
Write-Step "Checking Scoop..."
if (Get-Command scoop -ErrorAction SilentlyContinue) {
    Write-Skip "Scoop already installed."
} else {
    Write-Step "Installing Scoop..."
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
    $installer = Join-Path $env:TEMP 'scoop-install.ps1'
    Invoke-RestMethod -Uri https://get.scoop.sh -OutFile $installer
    # -RunAsAdmin lets the installer proceed when running in an elevated shell.
    if (Test-Admin) {
        & $installer -RunAsAdmin
    } else {
        & $installer
    }
    # Make scoop available in the current session.
    $env:Path = "$env:USERPROFILE\scoop\shims;$env:Path"
}

# --- 2. Ensure git (Scoop needs it to add/clone buckets) --------------------
# Must run *before* `scoop bucket add` below. git lives in the default `main`
# bucket, which needs no git itself, so it's safe to install first.
Write-Step "Ensuring git (required to add buckets)..."
if (Get-Command git -ErrorAction SilentlyContinue) {
    Write-Skip "git already installed."
} else {
    scoop install git
}

# --- 3. Add buckets ---------------------------------------------------------
# Only `extras` is needed (CLI tools). Nerd Fonts are NOT installed here: icon
# glyphs are rendered by the *client* terminal, not this (often headless/SSH)
# machine, so the font belongs on the client. See README for client setup.
$buckets = @('extras')
$haveBuckets = (scoop bucket list).Name
foreach ($b in $buckets) {
    Write-Step "Ensuring '$b' bucket..."
    if ($haveBuckets -contains $b) {
        Write-Skip "'$b' bucket already added."
    } else {
        scoop bucket add $b
    }
}

# --- 4. Install CLI tools ---------------------------------------------------
# (git is installed earlier in step 2, before buckets, so it's not repeated here.)
$tools = @(
    'gh',        # gh  - GitHub CLI
    'ripgrep',   # rg  - fast recursive search
    'fd',        # fd  - fast file finder
    'bat',       # bat - cat with syntax highlighting
    'fzf',       # fzf - fuzzy finder
    'jq',        # jq  - JSON processor
    '7zip',      # 7z  - archiver
    'eza',       # eza - modern ls / tree
    'vim',       # vim - text editor
    'zoxide'     # z   - smarter cd
)   # NOTE: pwsh (PowerShell 7) is expected to be already installed; the SSH
    #       step below just points the SSH default shell at it.
Write-Step "Installing CLI tools..."
$installed = (scoop list 6>$null | Select-Object -ExpandProperty Name)
foreach ($t in $tools) {
    if ($installed -contains $t) {
        Write-Skip "$t already installed."
    } else {
        scoop install $t
    }
}

# --- 5. Install PSFzf module (for Ctrl+R / Ctrl+T) --------------------------
Write-Step "Installing PSFzf module..."
if (Get-Module PSFzf -ListAvailable) {
    Write-Skip "PSFzf already installed."
} else {
    Install-Module -Name PSFzf -Scope CurrentUser -Force
}

# --- 6. Install the PowerShell profile --------------------------------------
if ($NoProfile) {
    Write-Skip "Profile install skipped (-NoProfile)."
} else {
    Write-Step "Installing PowerShell profile..."
    $src = Resolve-ConfigFile 'config/Microsoft.PowerShell_profile.ps1'
    if (-not $src) {
        # Warning already emitted by Resolve-ConfigFile.
    } else {
        $dir = Split-Path $PROFILE -Parent
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
        if (Test-Path $PROFILE) {
            $backup = "$PROFILE.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"
            Copy-Item $PROFILE $backup
            Write-Host "    Existing profile backed up to $backup" -ForegroundColor Yellow
        }
        Copy-Item $src $PROFILE -Force
        Write-Host "    Profile installed to $PROFILE" -ForegroundColor Green
    }
}

# --- 7. Install the vim config (_vimrc) -------------------------------------
if ($NoProfile) {
    Write-Skip "vim config install skipped (-NoProfile)."
} else {
    Write-Step "Installing vim config (_vimrc)..."
    $vimSrc = Resolve-ConfigFile 'config/_vimrc'
    $vimDst = Join-Path $HOME '_vimrc'
    if (-not $vimSrc) {
        # Warning already emitted by Resolve-ConfigFile.
    } else {
        # Persistent-undo dir referenced by the _vimrc (set undodir=...).
        $undoDir = Join-Path $HOME 'vimfiles\undo'
        if (-not (Test-Path $undoDir)) { New-Item -ItemType Directory -Force -Path $undoDir | Out-Null }
        if (Test-Path $vimDst) {
            $backup = "$vimDst.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"
            Copy-Item $vimDst $backup
            Write-Host "    Existing _vimrc backed up to $backup" -ForegroundColor Yellow
        }
        Copy-Item $vimSrc $vimDst -Force
        Write-Host "    _vimrc installed to $vimDst" -ForegroundColor Green
    }
}

# Git aliases are no longer configured here: they ship as oh-my-zsh-style shell
# shortcuts (gst / gco / gd / gp / ...) in the PowerShell profile installed in
# step 6, so they load in every shell without touching your ~/.gitconfig.

# --- 8. OpenSSH Server (requires an elevated/admin session) -----------------
# Installs the Windows OpenSSH Server feature, enables sshd, listens on ports
# 22 + 58888, restricts logins to admins/"openssh users", opens the firewall
# for both ports, and points the SSH default shell at pwsh so that
# `ssh <host>` lands in PowerShell 7 instead of cmd.exe.
$SshPorts = @(22, 58888)   # ports to listen on / open in the firewall
Write-Step "Configuring OpenSSH Server..."
if ($NoSsh) {
    Write-Skip "OpenSSH Server setup skipped (-NoSsh)."
} elseif (-not (Test-Admin)) {
    Write-Warning "OpenSSH Server setup needs an elevated session. Re-run this script as Administrator to enable it - skipping for now."
} else {
    # 1. Install the OpenSSH.Server capability (Feature on Demand) if missing.
    $sshCap = Get-WindowsCapability -Online -Name 'OpenSSH.Server*'
    if ($sshCap.State -ne 'Installed') {
        Write-Step "Installing OpenSSH.Server capability..."
        Add-WindowsCapability -Online -Name $sshCap.Name | Out-Null
    } else {
        Write-Skip "OpenSSH.Server already installed."
    }

    # 2. Start sshd now and have it launch automatically at boot.
    #    (The first start auto-generates the host keys and the default config.)
    Set-Service -Name sshd -StartupType Automatic
    if ((Get-Service sshd).Status -ne 'Running') { Start-Service sshd }

    # 3. Apply our sshd_config customizations (extra Port + AllowGroups), then
    #    restart sshd so they take effect. Add-SshdGlobalLines is idempotent and
    #    inserts before the trailing `Match` block.
    $sshdConfig = Join-Path $env:ProgramData 'ssh\sshd_config'
    $sshdLines = @($SshPorts | ForEach-Object { "Port $_" }) +
                 @('AllowGroups administrators "openssh users"')
    if (Add-SshdGlobalLines $sshdConfig $sshdLines) {
        Write-Step "Updated sshd_config (ports $($SshPorts -join ', ') + AllowGroups); restarting sshd..."
        Restart-Service sshd
    } else {
        Write-Skip "sshd_config already has the desired ports / AllowGroups."
    }

    # 4. Ensure an inbound firewall rule for each SSH port.
    foreach ($port in $SshPorts) {
        $ruleName = if ($port -eq 22) { 'OpenSSH-Server-In-TCP' } else { "OpenSSH-Server-In-TCP-$port" }
        if (Get-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue) {
            Write-Skip "Firewall rule '$ruleName' already present."
        } else {
            Write-Step "Adding firewall rule for SSH (TCP $port)..."
            New-NetFirewallRule -Name $ruleName -DisplayName "OpenSSH Server (sshd) Port $port" `
                -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort $port | Out-Null
        }
    }

    # 5. Point the SSH default shell at pwsh, matching what works on this box.
    #    Resolution order (all stable across pwsh upgrades):
    #      1) Program Files (MSI/winget) - present on CI runners
    #      2) WindowsApps execution alias (Store/MSIX) - what this box uses
    #      3) whatever `pwsh` is on PATH (last resort, version-stamped)
    #    Also set DefaultShellCommandOption '-c' so `ssh host <cmd>` works.
    $pwshPath = @(
        'C:\Program Files\PowerShell\7\pwsh.exe'
        "$env:LOCALAPPDATA\Microsoft\WindowsApps\pwsh.exe"
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $pwshPath) { $pwshPath = (Get-Command pwsh -ErrorAction SilentlyContinue).Source }
    if ($pwshPath) {
        New-ItemProperty -Path 'HKLM:\SOFTWARE\OpenSSH' -Name DefaultShell `
            -Value $pwshPath -PropertyType String -Force | Out-Null
        New-ItemProperty -Path 'HKLM:\SOFTWARE\OpenSSH' -Name DefaultShellCommandOption `
            -Value '-c' -PropertyType String -Force | Out-Null
        Write-Host "    SSH default shell set to $pwshPath (-c)" -ForegroundColor Green
    } else {
        Write-Warning "pwsh not found - install PowerShell 7, then re-run. Leaving SSH default shell unchanged."
    }
}

Write-Host ""
Write-Step "Done! Open a new PowerShell window (or run '. `$PROFILE') to load everything."
