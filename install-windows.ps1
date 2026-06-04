#requires -Version 5.1
<#
.SYNOPSIS
    One-shot setup for a modern Windows command-line environment.

.DESCRIPTION
    Installs the Scoop package manager, PowerShell 7, a set of common CLI tools,
    Node.js LTS, and the
    PSFzf module, then installs the bundled PowerShell profile that wires up
    aliases (eza/bat) and keybindings (fzf Ctrl+R / Ctrl+T) and zoxide.

    Safe to re-run: every step checks for existing installs before acting.

.EXAMPLE
    # From a normal (non-admin) PowerShell session:
    iwr -useb https://raw.githubusercontent.com/sunsheng/cli-workbench-setup/main/install-windows.ps1 | iex

.EXAMPLE
    # Or clone the repo and run locally:
    .\install-windows.ps1
#>
[CmdletBinding()]
param(
    # Skip the personal profile files; git aliases live in the shell profile.
    [switch]$NoProfile,
    # Skip the OpenSSH Server step (it also requires an elevated session).
    [switch]$NoSsh
)

$ErrorActionPreference = 'Stop'
$NodeMajor = 24

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch {
    # PowerShell 7+ does not depend on ServicePointManager for modern TLS.
}

function Write-Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
function Write-Skip($msg) { Write-Host "    (skip) $msg" -ForegroundColor DarkGray }

# True when the current session is elevated (Administrator).
function Test-Admin {
    ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Base URL for fetching bundled profile files when no local copy is available.
$RepoRawBase = 'https://raw.githubusercontent.com/sunsheng/cli-workbench-setup/main'

# Resolve a bundled profile file to a local path.
#   - Run from a clone (`$PSScriptRoot` set): use the file on disk.
#   - Run via `iwr ... | iex` (`$PSScriptRoot` empty): download it from GitHub.
# Returns $null (with a warning) if the file can't be obtained.
function Resolve-ProfileFile($relativePath) {   # e.g. 'profiles/windows-vimrc'
    if ($PSScriptRoot) {
        $local = Join-Path $PSScriptRoot ($relativePath -replace '/', '\')
        if (Test-Path $local) { return $local }
    }
    $url = "$RepoRawBase/$relativePath"
    $tmp = Join-Path $env:TEMP ('cli-workbench-' + (Split-Path $relativePath -Leaf))
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

function Add-PathEntry {
    param(
        [Parameter(Mandatory=$true)][string]$PathEntry,
        [switch]$Persist
    )

    if ([string]::IsNullOrWhiteSpace($PathEntry)) { return }
    if (-not (Test-Path $PathEntry)) { return }

    $needle = $PathEntry.TrimEnd('\')
    $sessionHasPath = @($env:Path.Split(';', [System.StringSplitOptions]::RemoveEmptyEntries) |
        Where-Object { $_.TrimEnd('\') -ieq $needle }).Count -gt 0
    if (-not $sessionHasPath) {
        $env:Path = "$PathEntry;$env:Path"
    }

    if ($Persist) {
        $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
        $userHasPath = -not [string]::IsNullOrWhiteSpace($userPath) -and
            @($userPath.Split(';', [System.StringSplitOptions]::RemoveEmptyEntries) |
                Where-Object { $_.TrimEnd('\') -ieq $needle }).Count -gt 0
        if (-not $userHasPath) {
            $newUserPath = if ([string]::IsNullOrWhiteSpace($userPath)) { $PathEntry } else { "$PathEntry;$userPath" }
            [Environment]::SetEnvironmentVariable('Path', $newUserPath, 'User')
        }
    }
}

function Get-NpmGlobalBinDir {
    if (-not (Get-Command npm -ErrorAction SilentlyContinue)) { return $null }
    try {
        $prefix = (& npm config get prefix 2>$null | Select-Object -First 1).Trim()
        if ([string]::IsNullOrWhiteSpace($prefix)) { return $null }
        if ($IsWindows -or $env:OS -eq 'Windows_NT') { return $prefix }
        return (Join-Path $prefix 'bin')
    } catch {
        return $null
    }
}

function Invoke-InHome {
    param(
        [Parameter(Mandatory=$true)][scriptblock]$Script
    )

    $oldLocation = Get-Location
    try {
        Set-Location -LiteralPath $HOME
        & $Script
    } finally {
        Set-Location -LiteralPath $oldLocation
    }
}

function Test-CliCommand {
    param(
        [Parameter(Mandatory=$true)][string]$Name
    )

    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if (-not $cmd) { return $false }

    try {
        & $cmd.Source --version *> $null
        return $LASTEXITCODE -eq 0
    } catch {
        return $false
    }
}

function Get-PwshCommand {
    Get-Command pwsh -ErrorAction SilentlyContinue
}

function Get-ScoopPackageExe {
    param(
        [Parameter(Mandatory=$true)][string]$Package,
        [Parameter(Mandatory=$true)][string]$ExeName
    )

    if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) { return $null }
    try {
        $prefix = (& scoop prefix $Package 2>$null | Select-Object -First 1).Trim()
        if ([string]::IsNullOrWhiteSpace($prefix)) { return $null }
        $exe = Join-Path $prefix $ExeName
        if (Test-Path $exe) { return $exe }
    } catch {
        return $null
    }
    return $null
}

function Get-PwshExePath {
    $candidates = @(
        'C:\Program Files\PowerShell\7\pwsh.exe',
        (Get-ScoopPackageExe -Package 'pwsh' -ExeName 'pwsh.exe'),
        "$env:USERPROFILE\scoop\shims\pwsh.exe",
        "$env:LOCALAPPDATA\Microsoft\WindowsApps\pwsh.exe"
    )
    foreach ($candidate in $candidates) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path $candidate)) {
            return $candidate
        }
    }

    $cmd = Get-PwshCommand
    if ($cmd) { return $cmd.Source }
    return $null
}

function Install-PowerShell7 {
    Write-Step "Ensuring PowerShell 7 (pwsh)..."
    if (Get-PwshCommand) {
        Write-Skip "pwsh already installed."
        return
    }

    scoop install pwsh
    Add-PathEntry -PathEntry "$env:USERPROFILE\scoop\shims" -Persist
    if (-not (Get-PwshCommand)) {
        throw "pwsh was not found after installation."
    }
}

function Install-PwshProfile {
    param(
        [Parameter(Mandatory=$true)][string]$SourcePath
    )

    $destinationPath = Join-Path $HOME 'Documents\PowerShell\Microsoft.PowerShell_profile.ps1'
    $dir = Split-Path $destinationPath -Parent
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    Copy-Item $SourcePath $destinationPath -Force
    Write-Host "    Profile installed to $destinationPath" -ForegroundColor Green
}

function Update-AiCliPath {
    $paths = @(
        (Join-Path $env:LOCALAPPDATA 'Programs\OpenAI\Codex\bin'),
        (Join-Path $HOME '.local\bin'),
        (Get-NpmGlobalBinDir),
        $(if ($env:APPDATA) { Join-Path $env:APPDATA 'npm' })
    )
    foreach ($path in $paths) {
        Add-PathEntry -PathEntry $path -Persist
    }
}

function Install-NpmGlobalPackage {
    param(
        [Parameter(Mandatory=$true)][string]$Package
    )

    if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
        throw "npm is required to install $Package."
    }
    Invoke-InHome { npm install -g $Package }
    Update-AiCliPath
}

function Install-CodexCli {
    Write-Step "Ensuring Codex CLI..."
    Update-AiCliPath
    if (Test-CliCommand codex) {
        Write-Skip "codex already installed."
        return
    }

    $oldNonInteractive = $env:CODEX_NON_INTERACTIVE
    try {
        if ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected) {
            $env:CODEX_NON_INTERACTIVE = '1'
        }
        $installer = Invoke-RestMethod -Uri 'https://chatgpt.com/codex/install.ps1'
        Invoke-InHome { & ([scriptblock]::Create($installer)) }
    } catch {
        Write-Warning "Codex official installer failed; falling back to npm: $($_.Exception.Message)"
        Install-NpmGlobalPackage '@openai/codex'
    } finally {
        if ($null -eq $oldNonInteractive) {
            Remove-Item Env:\CODEX_NON_INTERACTIVE -ErrorAction SilentlyContinue
        } else {
            $env:CODEX_NON_INTERACTIVE = $oldNonInteractive
        }
    }

    Update-AiCliPath
    if (-not (Test-CliCommand codex)) {
        Write-Step "Codex command still not found after official installer; falling back to npm..."
        Install-NpmGlobalPackage '@openai/codex'
    }
    if (-not (Test-CliCommand codex)) {
        throw "codex was not usable after installation."
    }
}

# Download the Claude Code native binary directly from downloads.claude.ai and run
# its built-in installer. The entry script at claude.ai/install.ps1 sits behind
# Cloudflare's managed challenge, which can 403 bare requests from datacenter IPs
# (cloud VMs); the downloads host has no such challenge. Returns $true on success,
# $false on any failure so the caller can fall back to the official installer or npm.
function Install-ClaudeNative {
    $base = 'https://downloads.claude.ai/claude-code-releases'
    $tmp = $null
    $oldProgress = $ProgressPreference
    try {
        $ProgressPreference = 'SilentlyContinue'
        $arch = switch ($env:PROCESSOR_ARCHITECTURE) {
            'AMD64' { 'x64' }
            'ARM64' { 'arm64' }
            default { throw "Unsupported architecture: $env:PROCESSOR_ARCHITECTURE" }
        }
        $platform = "win32-$arch"
        $ver = (Invoke-RestMethod -Uri "$base/latest").ToString().Trim()
        if ($ver -notmatch '^\d+\.\d+\.\d+') { throw "Unexpected version from downloads.claude.ai: $ver" }

        $node = (Invoke-RestMethod -Uri "$base/$ver/manifest.json").platforms.$platform
        if (-not $node -or [string]::IsNullOrWhiteSpace($node.checksum)) {
            throw "Platform $platform not found in manifest"
        }
        $binary = if ($node.binary) { $node.binary } else { 'claude.exe' }

        $tmp = Join-Path $env:TEMP "claude-$ver-$platform.exe"
        Invoke-WebRequest -Uri "$base/$ver/$platform/$binary" -OutFile $tmp
        $actual = (Get-FileHash $tmp -Algorithm SHA256).Hash.ToLower()
        if ($actual -ne $node.checksum.ToLower()) {
            throw "Checksum verification failed for $platform"
        }
        # Route the installer's console output to the host so it does not leak into
        # this function's return value.
        & $tmp install | Out-Host
        return $true
    } catch {
        Write-Warning "Claude Code native install failed: $($_.Exception.Message)"
        return $false
    } finally {
        $ProgressPreference = $oldProgress
        if ($tmp -and (Test-Path $tmp)) { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
    }
}

function Install-ClaudeCodeCli {
    Write-Step "Ensuring Claude Code CLI..."
    Update-AiCliPath
    if (Get-Command claude -ErrorAction SilentlyContinue) {
        Write-Skip "claude already installed."
        return
    }

    # Preferred: native binary direct from downloads.claude.ai (works from datacenter
    # IPs). Fallback 1: claude.ai/install.ps1. Fallback 2: npm.
    if (-not (Install-ClaudeNative)) {
        try {
            $installer = Invoke-RestMethod -Uri 'https://claude.ai/install.ps1'
            Invoke-InHome { & ([scriptblock]::Create($installer)) }
        } catch {
            Write-Warning "Claude Code official installer failed; falling back to npm: $($_.Exception.Message)"
            Install-NpmGlobalPackage '@anthropic-ai/claude-code'
        }
    }

    Update-AiCliPath
    if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
        Write-Step "Claude command still not found after installers; falling back to npm..."
        Install-NpmGlobalPackage '@anthropic-ai/claude-code'
    }
    if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
        throw "claude was not found after installation."
    }
}

# --- 1. Install Scoop -------------------------------------------------------
Write-Step "Checking Scoop..."
try {
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
} catch {
    Write-Warning "Could not set CurrentUser execution policy to RemoteSigned: $($_.Exception.Message)"
}
if (Get-Command scoop -ErrorAction SilentlyContinue) {
    Write-Skip "Scoop already installed."
} else {
    Write-Step "Installing Scoop..."
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
Add-PathEntry -PathEntry "$env:USERPROFILE\scoop\shims" -Persist

# --- 2. Ensure PowerShell 7 -------------------------------------------------
Install-PowerShell7

# --- 3. Ensure git (Scoop needs it to add/clone buckets) --------------------
# Must run *before* `scoop bucket add` below. git lives in the default `main`
# bucket, which needs no git itself, so it's safe to install first.
Write-Step "Ensuring git (required to add buckets)..."
if (Get-Command git -ErrorAction SilentlyContinue) {
    Write-Skip "git already installed."
} else {
    scoop install git
}

# --- 4. Add buckets ---------------------------------------------------------
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

# --- 5. Install CLI tools ---------------------------------------------------
# (git is installed earlier in step 3, before buckets, so it's not repeated here.)
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

# --- 6. Ensure Node.js LTS --------------------------------------------------
# Skip only when a usable node+npm toolchain is already present (the AI CLI npm
# fallback needs npm); otherwise install the Scoop LTS package.
Write-Step "Ensuring Node.js $NodeMajor.x LTS..."
if ((Get-Command node -ErrorAction SilentlyContinue) -and (Get-Command npm -ErrorAction SilentlyContinue)) {
    Write-Skip "node $(node --version) and npm already available."
} else {
    scoop install nodejs-lts
}

# --- 7. Install AI coding CLIs ----------------------------------------------
Install-CodexCli
Install-ClaudeCodeCli

# --- 8. Install PSFzf module (for Ctrl+R / Ctrl+T) --------------------------
Write-Step "Installing PSFzf module..."
$pwshExe = Get-PwshExePath
if ($pwshExe) {
    & $pwshExe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command @'
$ErrorActionPreference = 'Stop'
Install-Module -Name PSFzf -Scope CurrentUser -Force
'@
} else {
    throw "pwsh not found; cannot install PSFzf for PowerShell 7."
}

# --- 9. Install the PowerShell profile --------------------------------------
if ($NoProfile) {
    Write-Skip "Profile install skipped (-NoProfile)."
} else {
    Write-Step "Installing PowerShell profile..."
    $src = Resolve-ProfileFile 'profiles/powershell-profile.ps1'
    if (-not $src) {
        # Warning already emitted by Resolve-ProfileFile.
    } else {
        Install-PwshProfile -SourcePath $src
    }
}

# --- 10. Install the Windows Vim profile ------------------------------------
if ($NoProfile) {
    Write-Skip "Vim profile install skipped (-NoProfile)."
} else {
    Write-Step "Installing Windows Vim profile..."
    $vimSrc = Resolve-ProfileFile 'profiles/windows-vimrc'
    $vimDst = Join-Path $HOME '_vimrc'
    if (-not $vimSrc) {
        # Warning already emitted by Resolve-ProfileFile.
    } else {
        # Persistent-undo dir referenced by the Windows Vim profile.
        $undoDir = Join-Path $HOME 'vimfiles\undo'
        if (-not (Test-Path $undoDir)) { New-Item -ItemType Directory -Force -Path $undoDir | Out-Null }
        if (Test-Path $vimDst) {
            $backup = "$vimDst.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"
            Copy-Item $vimDst $backup
            Write-Host "    Existing _vimrc backed up to $backup" -ForegroundColor Yellow
        }
        Copy-Item $vimSrc $vimDst -Force
        Write-Host "    Windows Vim profile installed to $vimDst" -ForegroundColor Green
    }
}

# Git aliases are no longer configured here: they ship as oh-my-zsh-style shell
# shortcuts (gst / gco / gd / gp / ...) in the PowerShell profile installed in
# step 9, so they load in every shell without touching your ~/.gitconfig.

# --- 11. OpenSSH Server (requires an elevated/admin session) ----------------
# Installs the Windows OpenSSH Server feature, enables sshd, listens on port
# 58888 only (port 22 is left off to dodge internet-wide SSH brute-force),
# disables password auth (key-only via administrators_authorized_keys),
# restricts logins to admins/"openssh users", opens the firewall for that
# port, and points the SSH default shell at pwsh so that `ssh <host>` lands
# in PowerShell 7 instead of cmd.exe.
$SshPorts = @(58888)   # ports to listen on / open in the firewall
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

    # 3. Apply our sshd_config customizations (Port + AllowGroups + key-only
    #    auth), then restart sshd so they take effect. Add-SshdGlobalLines is
    #    idempotent and inserts before the trailing `Match` block.
    $sshdConfig = Join-Path $env:ProgramData 'ssh\sshd_config'
    $sshdLines = @($SshPorts | ForEach-Object { "Port $_" }) +
                 @('AllowGroups administrators "openssh users"',
                   'PasswordAuthentication no')
    if (Add-SshdGlobalLines $sshdConfig $sshdLines) {
        Write-Step "Updated sshd_config (port $($SshPorts -join ', ') + AllowGroups + key-only auth); restarting sshd..."
        Restart-Service sshd
    } else {
        Write-Skip "sshd_config already has the desired ports / AllowGroups."
    }

    # 4. Ensure an inbound firewall rule for each SSH port.
    foreach ($port in $SshPorts) {
        $ruleName = "OpenSSH-Server-In-TCP-$port"
        if (Get-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue) {
            Write-Skip "Firewall rule '$ruleName' already present."
        } else {
            Write-Step "Adding firewall rule for SSH (TCP $port)..."
            New-NetFirewallRule -Name $ruleName -DisplayName "OpenSSH Server (sshd) Port $port" `
                -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort $port | Out-Null
        }
    }

    # 5. Point the SSH default shell at pwsh, matching what works on this box.
    #    Resolution order:
    #      1) Program Files (MSI/winget)
    #      2) Scoop package directory installed above
    #      3) Scoop shim / WindowsApps / PATH as fallbacks
    #    Also set DefaultShellCommandOption '-c' so `ssh host <cmd>` works.
    $pwshPath = Get-PwshExePath
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
