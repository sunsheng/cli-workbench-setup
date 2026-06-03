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
    # Skip copying the bundled PowerShell profile into place.
    [switch]$NoProfile
)

$ErrorActionPreference = 'Stop'

function Write-Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
function Write-Skip($msg) { Write-Host "    (skip) $msg" -ForegroundColor DarkGray }

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
    if (([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        & $installer -RunAsAdmin
    } else {
        & $installer
    }
    # Make scoop available in the current session.
    $env:Path = "$env:USERPROFILE\scoop\shims;$env:Path"
}

# --- 2. Add buckets ---------------------------------------------------------
$buckets = @('extras', 'nerd-fonts')   # extras: CLI tools; nerd-fonts: icon fonts
$haveBuckets = (scoop bucket list).Name
foreach ($b in $buckets) {
    Write-Step "Ensuring '$b' bucket..."
    if ($haveBuckets -contains $b) {
        Write-Skip "'$b' bucket already added."
    } else {
        scoop bucket add $b
    }
}

# --- 3. Install a Nerd Font (icons for eza --icons / starship / etc.) --------
$font = 'FiraCode-NF'
Write-Step "Installing Nerd Font ($font)..."
if ((scoop list 6>$null | Select-Object -ExpandProperty Name) -contains $font) {
    Write-Skip "$font already installed."
} else {
    scoop install "nerd-fonts/$font"
    Write-Host "    Set your terminal font to 'FiraCode Nerd Font' to see icons." -ForegroundColor Yellow
}

# --- 4. Install CLI tools ---------------------------------------------------
$tools = @(
    'git',       # version control (also required by scoop for buckets)
    'gh',        # gh  - GitHub CLI
    'ripgrep',   # rg  - fast recursive search
    'fd',        # fd  - fast file finder
    'bat',       # bat - cat with syntax highlighting
    'fzf',       # fzf - fuzzy finder
    'jq',        # jq  - JSON processor
    '7zip',      # 7z  - archiver
    'eza',       # eza - modern ls / tree
    'lsd',       # lsd - another modern ls
    'vim',       # vim - text editor
    'zoxide'     # z   - smarter cd
)
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
    $src = Join-Path $PSScriptRoot 'config\Microsoft.PowerShell_profile.ps1'
    if (-not (Test-Path $src)) {
        Write-Warning "Bundled profile not found at $src - skipping."
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

Write-Host ""
Write-Step "Done! Open a new PowerShell window (or run '. `$PROFILE') to load everything."
