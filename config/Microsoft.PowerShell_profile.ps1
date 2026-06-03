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
# `zoxide init` forks the exe and prints the same script on every startup
# (~130ms). Cache its output and dot-source the cache instead; regenerate only
# when the cache is missing. After upgrading zoxide, delete the cache to refresh.
# Guarded so the profile doesn't error where zoxide isn't installed (e.g. after
# `install.ps1 -NoProfile`, or on a machine without the tools).
$zoxideCache = Join-Path (Split-Path $PROFILE) '.zoxide-init.ps1'
if (-not (Test-Path $zoxideCache)) {
    if (Get-Command zoxide -ErrorAction SilentlyContinue) {
        zoxide init powershell | Out-File -FilePath $zoxideCache -Encoding utf8
    }
}
if (Test-Path $zoxideCache) { . $zoxideCache }

# --- PSFzf: fuzzy history (Ctrl+R) and file search (Ctrl+T) ---
# Importing PSFzf at startup costs ~400ms, but most sessions never use fzf.
# Defer it: the Ctrl+R/Ctrl+T stubs below import PSFzf on first use, then hand
# off to its real handler. Set-PsFzfOption rebinds both chords to PSFzf's own
# handlers, so each stub runs at most once per session. The availability probe
# also moves here, off the startup path. Bound inside the PSReadLine guard.
$script:psfzfLoaded = $false
function Initialize-PSFzf {
    if ($script:psfzfLoaded) { return }
    $script:psfzfLoaded = $true
    if (-not (Get-Module PSFzf -ListAvailable)) { return }
    Import-Module PSFzf
    Set-PsFzfOption -PSReadlineChordProvider 'Ctrl+t' -PSReadlineChordReverseHistory 'Ctrl+r'
}

if (Get-Module PSReadLine -ListAvailable) {
    Set-PSReadLineKeyHandler -Chord 'Ctrl+r' -ScriptBlock {
        Initialize-PSFzf
        Invoke-FzfPsReadlineHandlerHistory
    }
    Set-PSReadLineKeyHandler -Chord 'Ctrl+t' -ScriptBlock {
        Initialize-PSFzf
        Invoke-FzfPsReadlineHandlerProvider
    }

    # --- Ctrl+D: bash-style EOF — delete char under cursor, or exit on empty line ---
    # Use PSReadLine's built-in DeleteCharOrExit. Calling `exit` from a custom
    # scriptblock handler runs in a child scope and does NOT reliably close the
    # host, so the previous scriptblock version did nothing on an empty line.
    Set-PSReadLineKeyHandler -Chord 'Ctrl+d' -Function DeleteCharOrExit
}
