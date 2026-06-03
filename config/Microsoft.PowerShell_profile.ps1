# ===== Modern CLI tool aliases (installed via Scoop) =====

# Force UTF-8 output so Nerd Font icons (and any non-ASCII) render correctly.
# Matters most over SSH, where the session can start with a non-UTF-8 codepage
# and otherwise mangles eza's icon glyphs into '?'.
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# Ensure scoop shims are on PATH (usually already added by installer)
if ($env:Path -notlike "*$env:USERPROFILE\scoop\shims*") {
    $env:Path = "$env:USERPROFILE\scoop\shims;$env:Path"
}

# --- eza: modern replacement for ls / tree ---
# Remove the built-in `ls` alias (Get-ChildItem) so we can repoint it to eza.
# Icons require a Nerd Font (installed by install.ps1); set the terminal font
# to "FiraCode Nerd Font" for them to render correctly.
if (Test-Path Alias:ls) { Remove-Item Alias:ls -Force }
function ls  { eza --icons --group-directories-first @args }                 # plain listing
function ll  { eza --icons -la --group-directories-first --git @args }       # long, with hidden + git status
function la  { eza --icons -a  --group-directories-first @args }             # all files
function lt  { eza --icons --tree --level=2 @args }                          # tree view, 2 levels (replaces `tree`)
function tree { eza --icons --tree @args }                                   # full tree

# --- bat: cat with syntax highlighting ---
# PowerShell `cat` aliases Get-Content; remove it and repoint to bat.
if (Test-Path Alias:cat) { Remove-Item Alias:cat -Force }
function cat { bat @args }

# --- zoxide: smarter cd (use `z <dir>` to jump, `zi` for interactive) ---
Invoke-Expression (& { (zoxide init powershell | Out-String) })

# --- PSFzf: fuzzy history (Ctrl+R) and file search (Ctrl+T) ---
Import-Module PSFzf
Set-PsFzfOption -PSReadlineChordProvider 'Ctrl+t' -PSReadlineChordReverseHistory 'Ctrl+r'
