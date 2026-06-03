# ===== Modern CLI tool aliases (installed via Scoop) =====

# Ensure scoop shims are on PATH (usually already added by installer)
if ($env:Path -notlike "*$env:USERPROFILE\scoop\shims*") {
    $env:Path = "$env:USERPROFILE\scoop\shims;$env:Path"
}

# --- eza: modern replacement for ls / tree ---
# Remove the built-in `ls` alias (Get-ChildItem) so we can repoint it to eza.
if (Test-Path Alias:ls) { Remove-Item Alias:ls -Force }
function ls  { eza --group-directories-first @args }                 # plain listing
function ll  { eza -la --group-directories-first --git @args }       # long, with hidden + git status
function la  { eza -a  --group-directories-first @args }             # all files
function lt  { eza --tree --level=2 @args }                          # tree view, 2 levels (replaces `tree`)
function tree { eza --tree @args }                                   # full tree

# --- bat: cat with syntax highlighting ---
# PowerShell `cat` aliases Get-Content; remove it and repoint to bat.
if (Test-Path Alias:cat) { Remove-Item Alias:cat -Force }
function cat { bat @args }

# --- zoxide: smarter cd (use `z <dir>` to jump, `zi` for interactive) ---
Invoke-Expression (& { (zoxide init powershell | Out-String) })

# --- PSFzf: fuzzy history (Ctrl+R) and file search (Ctrl+T) ---
Import-Module PSFzf
Set-PsFzfOption -PSReadlineChordProvider 'Ctrl+t' -PSReadlineChordReverseHistory 'Ctrl+r'
