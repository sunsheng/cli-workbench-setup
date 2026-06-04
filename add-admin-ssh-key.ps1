#requires -Version 5.1
<#
.SYNOPSIS
    Add an SSH public key to Windows OpenSSH administrators_authorized_keys.

.DESCRIPTION
    Appends a public key to %ProgramData%\ssh\administrators_authorized_keys,
    avoids duplicates, and fixes the ACL required by Windows OpenSSH for
    administrator key login.

    Must be run from an elevated PowerShell session.

.EXAMPLE
    .\add-admin-ssh-key.ps1 -PublicKeyPath $HOME\.ssh\id_ed25519.pub

.EXAMPLE
    .\add-admin-ssh-key.ps1 -PublicKey 'ssh-ed25519 AAAA... user@host'
#>
[CmdletBinding(DefaultParameterSetName = 'Path')]
param(
    # SSH public key text, for example: ssh-ed25519 AAAA... user@host
    [Parameter(Mandatory = $true, ParameterSetName = 'Text')]
    [ValidateNotNullOrEmpty()]
    [string]$PublicKey,

    # Path to a .pub file. Defaults to common keys under $HOME\.ssh.
    [Parameter(ParameterSetName = 'Path')]
    [ValidateNotNullOrEmpty()]
    [string]$PublicKeyPath
)

$ErrorActionPreference = 'Stop'

function Write-Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
function Write-Skip($msg) { Write-Host "    (skip) $msg" -ForegroundColor DarkGray }

function Test-Admin {
    ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Resolve-DefaultPublicKeyPath {
    $candidates = @(
        (Join-Path $HOME '.ssh\id_ed25519.pub'),
        (Join-Path $HOME '.ssh\id_rsa.pub'),
        (Join-Path $HOME '.ssh\id_ecdsa.pub')
    )
    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) { return $candidate }
    }
    return $null
}

function ConvertTo-PublicKeyLine {
    param([Parameter(Mandatory = $true)][string]$Line)

    $trimmed = $Line.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed)) {
        throw "Public key is empty."
    }

    $parts = $trimmed -split '\s+'
    if ($parts.Count -lt 2) {
        throw "Public key must contain at least a key type and key body."
    }

    $validTypes = @(
        'ssh-rsa',
        'ssh-ed25519',
        'ecdsa-sha2-nistp256',
        'ecdsa-sha2-nistp384',
        'ecdsa-sha2-nistp521',
        'sk-ssh-ed25519@openssh.com',
        'sk-ecdsa-sha2-nistp256@openssh.com'
    )
    if ($validTypes -notcontains $parts[0]) {
        throw "Unsupported or invalid SSH public key type '$($parts[0])'."
    }

    try {
        [Convert]::FromBase64String($parts[1]) | Out-Null
    } catch {
        throw "Public key body is not valid base64."
    }

    return ($parts -join ' ')
}

function Set-AdministratorsAuthorizedKeysAcl {
    param([Parameter(Mandatory = $true)][string]$Path)

    # Windows OpenSSH rejects administrator key files that are writable by
    # ordinary users. SID-based ACLs avoid locale-specific group names.
    $administratorsSid = New-Object System.Security.Principal.SecurityIdentifier 'S-1-5-32-544'
    $systemSid = New-Object System.Security.Principal.SecurityIdentifier 'S-1-5-18'
    $acl = Get-Acl -Path $Path

    $acl.SetAccessRuleProtection($true, $false)
    foreach ($rule in @($acl.Access)) {
        [void]$acl.RemoveAccessRuleSpecific($rule)
    }

    $rights = [System.Security.AccessControl.FileSystemRights]::FullControl
    $inheritance = [System.Security.AccessControl.InheritanceFlags]::None
    $propagation = [System.Security.AccessControl.PropagationFlags]::None
    $allow = [System.Security.AccessControl.AccessControlType]::Allow

    $administratorsRule = New-Object System.Security.AccessControl.FileSystemAccessRule `
        -ArgumentList $administratorsSid, $rights, $inheritance, $propagation, $allow
    $systemRule = New-Object System.Security.AccessControl.FileSystemAccessRule `
        -ArgumentList $systemSid, $rights, $inheritance, $propagation, $allow

    $acl.AddAccessRule($administratorsRule)
    $acl.AddAccessRule($systemRule)
    $acl.SetOwner($administratorsSid)
    Set-Acl -Path $Path -AclObject $acl
}

if (-not (Test-Admin)) {
    throw "This script must run from an elevated PowerShell session (Run as Administrator)."
}

if ($PSCmdlet.ParameterSetName -eq 'Path') {
    if ([string]::IsNullOrWhiteSpace($PublicKeyPath)) {
        $PublicKeyPath = Resolve-DefaultPublicKeyPath
        if (-not $PublicKeyPath) {
            throw "No public key path was provided and no default key was found under $HOME\.ssh."
        }
    }

    if (-not (Test-Path $PublicKeyPath)) {
        throw "Public key file not found: $PublicKeyPath"
    }

    $PublicKey = Get-Content -Path $PublicKeyPath -Raw
}

$keyLine = ConvertTo-PublicKeyLine -Line $PublicKey
$sshDir = Join-Path $env:ProgramData 'ssh'
$authorizedKeysPath = Join-Path $sshDir 'administrators_authorized_keys'

Write-Step "Ensuring $authorizedKeysPath..."
New-Item -ItemType Directory -Force -Path $sshDir | Out-Null
if (-not (Test-Path $authorizedKeysPath)) {
    New-Item -ItemType File -Force -Path $authorizedKeysPath | Out-Null
}

$existingKeys = @()
if ((Get-Item $authorizedKeysPath).Length -gt 0) {
    $existingKeys = @(Get-Content -Path $authorizedKeysPath | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

if ($existingKeys -contains $keyLine) {
    Write-Skip "Public key already exists."
} else {
    Add-Content -Path $authorizedKeysPath -Value $keyLine -Encoding ascii
    Write-Host "    Public key added." -ForegroundColor Green
}

Set-AdministratorsAuthorizedKeysAcl -Path $authorizedKeysPath
Write-Host "    ACL fixed: Administrators and SYSTEM only." -ForegroundColor Green
Write-Step "Done."
