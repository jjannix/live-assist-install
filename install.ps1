<#
.SYNOPSIS
    One-click installer for jnk Live Assist — OBS remote control.
.DESCRIPTION
    Paste into PowerShell (Win+X, Terminal):
        irm https://raw.githubusercontent.com/jjannix/live-assist-install/main/install.ps1 | iex

    Checks for Git, Node.js (x64), OBS Studio.  Installs missing tools via
    winget with a single keystroke.  Clones the repo, installs deps, and
    bootstraps a .env file.
.PARAMETER InstallDir
    Where to install.  Default: ~\jnk-live-assist
    Set via env: $env:JNK_INSTALL_DIR
.PARAMETER Yes
    Auto-install missing dependencies without asking.
    Set via env: $env:JNK_YES = 1
.PARAMETER Branch
    Git branch.  Default: main
    Set via env: $env:JNK_BRANCH
#>

[CmdletBinding()]
param(
    [string]$InstallDir,
    [switch]$Yes,
    [string]$Branch
)

# Resolve from env vars if not passed explicitly
if (-not $InstallDir) { $InstallDir = $env:JNK_INSTALL_DIR }
if (-not $InstallDir) { $InstallDir = Join-Path $env:USERPROFILE 'jnk-live-assist' }
if (-not $Branch)     { $Branch     = $env:JNK_BRANCH }
if (-not $Branch)     { $Branch     = 'main' }
if (-not $Yes)        { $Yes        = ($env:JNK_YES -eq '1') }

$ErrorActionPreference = 'Stop'
$RepoOwner = $env:JNK_REPO
if (-not $RepoOwner)  { $RepoOwner = 'jjannix/live-assist' }
$RepoUrl = "https://github.com/$RepoOwner.git"

# Track overall timing
$ScriptStart = Get-Date
$PhaseTimes  = @{}
$Checklist   = @{}   # key -> 'pass' | 'warn' | 'fail' | 'skip'

# =====================================================================
#  Helpers
# =====================================================================

function Write-Separator { Write-Host ('  ' + ('-' * 42)) -ForegroundColor DarkGray }

function Write-Phase($num, $msg) {
    $elapsed = if ($ScriptStart) { [int]((Get-Date) - $ScriptStart).TotalSeconds } else { 0 }
    Write-Host ''
    Write-Host "  [$num/5] $msg" -ForegroundColor Cyan -NoNewline
    Write-Host "   (${elapsed}s elapsed)" -ForegroundColor DarkGray
}

function Write-Plus($msg)   { Write-Host "    [+] $msg" -ForegroundColor Green }
function Write-Bang($msg)   { Write-Host "    [!] $msg" -ForegroundColor Yellow }
function Write-Cross($msg)  { Write-Host "    [x] $msg" -ForegroundColor Red }
function Write-Info($msg)   { Write-Host "        $msg" -ForegroundColor DarkGray }
function Write-Bold($msg)   { Write-Host "    $msg" -ForegroundColor White }
function Die($reason)       { Write-Cross $reason; throw $reason }

function Write-Banner {
    Write-Host ''
    Write-Host '  +--------------------------------------------------+' -ForegroundColor Magenta
    Write-Host '  |                                                  |' -ForegroundColor Magenta
    Write-Host '  |        jnk Live Assist — One-Click Setup         |' -ForegroundColor Magenta
    Write-Host '  |          OBS remote control for events            |' -ForegroundColor Magenta
    Write-Host '  |                                                  |' -ForegroundColor Magenta
    Write-Host '  +--------------------------------------------------+' -ForegroundColor Magenta
    Write-Host ''
}

function Refresh-Path {
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user    = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = ($machine, $user -join ';') -replace ';;+', ';'
}

function Find-Exe($candidates) {
    foreach ($name in $candidates) {
        $found = Get-Command $name -ErrorAction SilentlyContinue
        if ($found) { return $found.Source }
    }
    return $null
}

function Prompt-YesNo($question, $defaultYes = $true) {
    if ($Yes) {
        Write-Info "(auto-answered yes via `$env:JNK_YES)"
        return $true
    }
    $yn = if ($defaultYes) { 'Y/n' } else { 'y/N' }
    $answer = Read-Host "        $question  [$yn]"
    if ([string]::IsNullOrWhiteSpace($answer)) { return $defaultYes }
    return $answer.Trim().ToLowerInvariant().StartsWith('y')
}

# =====================================================================
#  Sanity checks
# =====================================================================

if ($PSVersionTable.PSVersion.Major -lt 5) {
    Die "PowerShell 5.0+ required (you have $($PSVersionTable.PSVersion))."
}

if (-not [Net.ServicePointManager]::SecurityProtocol.HasFlag([Net.SecurityProtocolType]::Tls12)) {
    [Net.ServicePointManager]::SecurityProtocol += [Net.SecurityProtocolType]::Tls12
}

$winget = Get-Command winget.exe -ErrorAction SilentlyContinue

# =====================================================================
#  Phase 1 — Prerequisites
# =====================================================================

function Install-Git {
    if ($winget) {
        Write-Info 'Running winget install Git.Git ...'
        winget install --id Git.Git --accept-source-agreements --accept-package-agreements --silent
        Refresh-Path
        $gitExe = Find-Exe @('git', "$env:ProgramFiles\Git\cmd\git.exe", "$env:ProgramFiles\Git\bin\git.exe")
        if ($gitExe) { Write-Plus "Installed to $gitExe"; $Checklist['git'] = 'pass'; return $true }
    }
    Write-Bang 'Could not auto-install Git.'
    Write-Info 'Download:  https://git-scm.com/download/win'
    Write-Info '(Choose 64-bit, accept defaults, then re-run this script.)'
    $Checklist['git'] = 'fail'
    return $false
}

function Ensure-Git {
    $gitExe = Find-Exe @('git', "$env:ProgramFiles\Git\cmd\git.exe", "$env:ProgramFiles\Git\bin\git.exe")
    if ($gitExe) {
        $ver = (& $gitExe --version 2>$null) -replace 'git version ', ''
        Write-Plus "Git $ver"
        $gitDir = Split-Path $gitExe -Parent
        if ($env:Path -notlike "*$gitDir*") { $env:Path = "$gitDir;$env:Path" }
        $Checklist['git'] = 'pass'
        return $true
    }
    Write-Bang 'Git is not installed.'
    if (Prompt-YesNo 'Install Git automatically?') {
        return Install-Git
    }
    $Checklist['git'] = 'fail'
    return $false
}

function Install-Node {
    if ($winget) {
        Write-Info 'Running winget install OpenJS.NodeJS.LTS ...'
        winget install --id OpenJS.NodeJS.LTS --accept-source-agreements --accept-package-agreements --silent
        Refresh-Path
        $nodeExe = Find-Exe @('node', "$env:ProgramFiles\nodejs\node.exe", "${env:ProgramFiles(x86)}\nodejs\node.exe")
        if ($nodeExe) { Write-Plus "Installed to $nodeExe"; $Checklist['node'] = 'pass'; return $nodeExe }
    }
    Write-Bang 'Could not auto-install Node.js.'
    Write-Info 'Download x64 LTS:  https://nodejs.org/'
    $Checklist['node'] = 'fail'
    return $null
}

function Ensure-Node {
    $nodeExe = Find-Exe @('node', "$env:ProgramFiles\nodejs\node.exe", "${env:ProgramFiles(x86)}\nodejs\node.exe")
    if (-not $nodeExe) {
        Write-Bang 'Node.js is not installed.'
        if (Prompt-YesNo 'Install Node.js LTS (x64) automatically?') {
            $nodeExe = Install-Node
            if (-not $nodeExe) { return $null }
        } else {
            $Checklist['node'] = 'fail'
            return $null
        }
    }

    $arch = & $nodeExe -p 'process.arch'
    $ver  = (& $nodeExe -v).Trim()

    # Validate architecture — native-sound-mixer is x64-only.
    # On ARM64, this is a soft warning (user may use AUDIO_BACKEND=none).
    if ($arch -ne 'x64') {
        Write-Bang "Node is $arch, but native-sound-mixer needs x64."
        Write-Info 'On ARM64 Windows the x64 Node.js runs fine via emulation.'
        Write-Info 'Alternatively set AUDIO_BACKEND=none in .env to skip audio.'
        if ($winget -and (Prompt-YesNo 'Re-install x64 Node via winget?')) {
            winget install --id OpenJS.NodeJS.LTS --accept-source-agreements --accept-package-agreements --silent --force
            Refresh-Path
            $newNode = Find-Exe @('node', "$env:ProgramFiles\nodejs\node.exe")
            if ($newNode) { $nodeExe = $newNode; $arch = & $nodeExe -p 'process.arch' }
        }
    }

    $nodeDir = Split-Path $nodeExe -Parent
    if ($env:Path -notlike "*$nodeDir*") { $env:Path = "$nodeDir;$env:Path" }
    Write-Plus "Node $ver  ($arch)"
    if ($arch -eq 'x64') { $Checklist['node'] = 'pass' } else { $Checklist['node'] = 'warn' }
    return $nodeExe
}

function Install-OBS {
    if (-not $winget) {
        Write-Bang 'winget not available — cannot auto-install OBS.'
        Write-Info 'Download:  https://obsproject.com/download'
        return $false
    }
    Write-Info 'winget install OBSProject.OBSStudio  (this may take a few minutes) ...'
    winget install -e --id OBSProject.OBSStudio --accept-source-agreements --accept-package-agreements --silent
    Refresh-Path
    $obsExe = Find-Exe @('obs64', "$env:ProgramFiles\obs-studio\bin\64bit\obs64.exe",
                          "${env:ProgramFiles(x86)}\obs-studio\bin\64bit\obs64.exe")
    if ($obsExe) {
        Write-Plus "OBS Studio installed at $obsExe"
        return $true
    }
    Write-Bang 'Could not auto-install OBS.'
    Write-Info 'Download:  https://obsproject.com/download'
    return $false
}

function Ensure-OBS {
    $obsExe = Find-Exe @('obs64', "$env:ProgramFiles\obs-studio\bin\64bit\obs64.exe",
                          "${env:ProgramFiles(x86)}\obs-studio\bin\64bit\obs64.exe")
    if (-not $obsExe) {
        Write-Bang 'OBS Studio is not installed.'
        if (Prompt-YesNo 'Install OBS Studio automatically?  (~200 MB)') {
            if (-not (Install-OBS)) { $Checklist['obs'] = 'warn'; return $false }
            $obsExe = Find-Exe @('obs64', "$env:ProgramFiles\obs-studio\bin\64bit\obs64.exe",
                                  "${env:ProgramFiles(x86)}\obs-studio\bin\64bit\obs64.exe")
            if (-not $obsExe) { $Checklist['obs'] = 'warn'; return $false }
        } else {
            Write-Info 'Download:  https://obsproject.com/download'
            Write-Info '(After installing, enable WebSocket: OBS -> Tools -> WebSocket Server Settings)'
            $Checklist['obs'] = 'warn'
            return $false
        }
    }

    # Read version — WebSocket is built-in starting with OBS 28
    $obsVer = (Get-Item $obsExe).VersionInfo.ProductVersion
    $majorOk = $true
    if ($obsVer -match '^(\d+)\.') {
        if ([int]$Matches[1] -lt 28) {
            Write-Bang "OBS $obsVer is too old (need 28+ for built-in WebSocket)."
            Write-Info 'Update at  https://obsproject.com/download'
            $majorOk = $false
        }
    }
    if ($majorOk) {
        Write-Plus "OBS Studio $obsVer"
    }

    # Quick WebSocket reachability probe (only works when OBS is running)
    try {
        $null = Invoke-RestMethod -Uri 'http://localhost:4455' -Method Get -TimeoutSec 2
        Write-Plus 'OBS WebSocket reachable on port 4455'
    } catch {
        Write-Info 'OBS WebSocket not reachable (OBS likely not running).'
        Write-Info 'Enable it:  OBS -> Tools -> WebSocket Server Settings -> Enable'
    }

    $Checklist['obs'] = if ($majorOk) { 'pass' } else { 'warn' }
    return $majorOk
}

# =====================================================================
#  Phase 2 — Clone / update
# =====================================================================

function Install-Repo {
    $gitExe = (Get-Command git -ErrorAction SilentlyContinue).Source
    if (-not $gitExe) { Die 'Git is required. Please install it and re-run.' }

    if (Test-Path (Join-Path $InstallDir '.git')) {
        Write-Info "Updating existing install ..."
        Push-Location $InstallDir
        try {
            & $gitExe fetch --depth 1 --quiet origin $Branch
            & $gitExe reset --hard --quiet "origin/$Branch"
            Write-Plus 'Repo updated to latest.'
        } finally { Pop-Location }
    } else {
        if (Test-Path $InstallDir) {
            if (-not (Prompt-YesNo "Path '$InstallDir' exists but is not a git repo.  Overwrite?" $false)) {
                Die 'Installation cancelled.  Set a different $env:JNK_INSTALL_DIR.'
            }
            Remove-Item $InstallDir -Recurse -Force
        }
        Write-Info "Cloning $RepoUrl ..."
        $parent = Split-Path $InstallDir -Parent
        if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        & $gitExe clone --depth 1 --quiet -b $Branch $RepoUrl $InstallDir
        if ($LASTEXITCODE -ne 0) { Die 'git clone failed — check your internet connection.' }
        Write-Plus 'Repo cloned.'
    }
    # Copy the installer itself into the install dir so it's self-contained
    $dest = Join-Path $InstallDir 'install.ps1'
    if ($PSCommandPath -and (Test-Path $PSCommandPath) -and $PSCommandPath -ne $dest) {
        try { Copy-Item $PSCommandPath $dest -Force -ErrorAction Stop } catch {
            try { Get-Content $PSCommandPath -Raw | Set-Content -Path $dest -Encoding UTF8 -ErrorAction Stop } catch {}
        }
    } elseif (-not (Test-Path $dest)) {
        try {
            $me = Invoke-RestMethod -UseBasicParsing 'https://raw.githubusercontent.com/jjannix/live-assist-install/main/install.ps1'
            Set-Content -Path $dest -Value $me -Encoding UTF8 -ErrorAction Stop
        } catch {}
    }

    $Checklist['repo'] = 'pass'
}

# =====================================================================
#  Phase 3 — npm install
# =====================================================================

function Install-Deps {
    Push-Location $InstallDir
    try {
        $npmExe = Find-Exe @('npm.cmd', 'npm', "$env:ProgramFiles\nodejs\npm.cmd")

        # Run npm install silently, show only clean summary
        Write-Info 'npm install  (this may take a minute) ...'
        if ($npmExe) {
            $prevEAP = $ErrorActionPreference
            $ErrorActionPreference = 'Continue'
            $npmOutput = & $npmExe install --no-audit --no-fund --loglevel=error 2>&1
            $ErrorActionPreference = $prevEAP
            # Show only useful summary lines
            foreach ($line in $npmOutput) {
                $s = "$line".Trim()
                if ($s -match '^(up to date|added|removed|changed|audited|found)') {
                    Write-Info $s
                }
            }
        } else {
            $nodeExe = Find-Exe @('node', "$env:ProgramFiles\nodejs\node.exe")
            if (-not $nodeExe) { Die 'Node.js is required.' }
            & $nodeExe -e "require('child_process').execSync('npm install --no-audit --no-fund --loglevel=error', {stdio:'inherit'})"
        }

        if ($LASTEXITCODE -ne 0) {
            # npm rolls back the ENTIRE install when a native build fails,
            # leaving node_modules empty — not even express. That makes the
            # app unstartable, so "just set AUDIO_BACKEND=none" is no help.
            # Retry with --ignore-scripts: installs every pure-JS dep but
            # skips native compilation. The app starts and OBS scene
            # switching works; only per-app volume is unavailable, and the
            # 'auto' backend already falls back gracefully at runtime.
            Write-Bang 'npm install failed — likely native-sound-mixer needs a C++ compiler.'
            Write-Info 'Retrying with --ignore-scripts so the app can still start ...'
            if (Test-Path (Join-Path $InstallDir 'node_modules')) {
                Remove-Item (Join-Path $InstallDir 'node_modules') -Recurse -Force -ErrorAction SilentlyContinue
            }
            $prevEAP = $ErrorActionPreference
            $ErrorActionPreference = 'Continue'
            if ($npmExe) {
                $retryOutput = & $npmExe install --no-audit --no-fund --loglevel=error --ignore-scripts 2>&1
            } else {
                $nodeExe = Find-Exe @('node', "$env:ProgramFiles\nodejs\node.exe")
                & $nodeExe -e "require('child_process').execSync('npm install --no-audit --no-fund --loglevel=error --ignore-scripts', {stdio:'inherit'})"
                $retryOutput = @()
            }
            $ErrorActionPreference = $prevEAP
            foreach ($line in $retryOutput) {
                $s = "$line".Trim()
                if ($s -match '^(up to date|added|removed|changed|audited|found)') { Write-Info $s }
            }

            if ($LASTEXITCODE -eq 0 -and (Test-Path (Join-Path $InstallDir 'node_modules\express'))) {
                Write-Plus 'Dependencies installed (audio module skipped).'
                Write-Bang 'OBS scene switching works now. Per-app volume is OFF until build tools are installed.'
                Write-Info 'For full audio, install the free Visual Studio Build Tools:'
                Write-Info '  https://visualstudio.microsoft.com/downloads/#build-tools-for-visual-studio-2022'
                Write-Info '  (select "Desktop development with C++"), then re-run this installer.'
                $Checklist['npm'] = 'warn'
            } else {
                Write-Cross 'Dependencies still failed to install. Check the output above.'
                Write-Info 'You can retry manually in the install folder:  npm.cmd install'
                $Checklist['npm'] = 'fail'
            }
            return
        }
        Write-Plus 'Dependencies installed.'
        $Checklist['npm'] = 'pass'
    } finally { Pop-Location }
}

# =====================================================================
#  Phase 4 — Configuration
# =====================================================================

function Bootstrap-Env {
    $envFile    = Join-Path $InstallDir '.env'
    $envExample = Join-Path $InstallDir '.env.example'

    if (Test-Path $envFile) {
        Write-Info '.env already exists — leaving it untouched.'
        $Checklist['env'] = 'pass'
        return
    }
    if (-not (Test-Path $envExample)) {
        Write-Bang '.env.example not found — skipping.'
        $Checklist['env'] = 'warn'
        return
    }
    Copy-Item $envExample $envFile -Force
    Write-Plus 'Created .env from .env.example.'
    Write-Bang 'Next step: set your OBS WebSocket password.'
    Write-Info '  1. In OBS:  Tools -> WebSocket Server Settings -> copy the password.'
    Write-Info '  2. Start the server (.\start.bat), then open the in-app Settings page:'
    Write-Info '     http://localhost:3000/config.html   (or tap the gear icon in the app)'
    Write-Info '  No need to edit .env by hand — paste the password into Settings and Save.'
    $Checklist['env'] = 'warn'
}

# =====================================================================
#  Phase 5 — Summary
# =====================================================================

function Write-Summary {
    $totalSec = [int]((Get-Date) - $ScriptStart).TotalSeconds
    Write-Host ''
    Write-Host '  +--------------------------------------------------+' -ForegroundColor Cyan
    Write-Host '  |               S E T U P   D O N E                |' -ForegroundColor Cyan
    Write-Host '  +--------------------------------------------------+' -ForegroundColor Cyan
    Write-Host ''

    # Mini report card
    $items = @(
        @{label='Git';         key='git'},
        @{label='Node.js';     key='node'},
        @{label='OBS Studio';  key='obs'},
        @{label='Repository';  key='repo'},
        @{label='npm packages';key='npm'},
        @{label='.env config'; key='env'}
    )

    foreach ($i in $items) {
        $status = $Checklist[$i.key]
        $icon   = switch ($status) {
            'pass' { ' [+]' }
            'warn' { ' [!]' }
            'fail' { ' [x]' }
            default { '  ? ' }
        }
        $colorMap = @{ pass = 'Green'; warn = 'Yellow'; fail = 'Red' }
        $textMap  = @{ pass = 'OK';   warn = 'needs attention'; fail = 'MISSING' }
        $color    = if ($colorMap.ContainsKey($status)) { $colorMap[$status] } else { 'DarkGray' }
        $text     = if ($textMap.ContainsKey($status))  { $textMap[$status] }  else { 'unknown' }
        $label    = '{0,-16}' -f $i.label
        Write-Host "  $icon  $label  " -ForegroundColor $color -NoNewline
        Write-Host $text
    }

    Write-Host ''
    Write-Host "  Finished in $totalSec seconds." -ForegroundColor DarkGray
    Write-Host ''

    # Launch instructions
    Write-Host '  -------  Start it  ---------------------------------' -ForegroundColor Cyan
    Write-Host ''
    Write-Bold ('  cd "' + $InstallDir + '"')
    Write-Bold '  .\start.bat'
    Write-Host ''
    Write-Host '  Then open on your phone:  http://localhost:3000' -ForegroundColor Cyan
    Write-Host ''
    Write-Host '  (To start just the server without OBS launcher:' -ForegroundColor DarkGray
    Write-Info ('cd "' + $InstallDir + '"')
    Write-Info 'node server.js'
    Write-Host '  )' -ForegroundColor DarkGray
    Write-Host ''

    # Generate & open onboarding page
    Write-OnboardingPage
}

function Write-OnboardingPage {
    $htmlFile = Join-Path $InstallDir 'onboarding.html'
    $elapsed  = [int]((Get-Date) - $ScriptStart).TotalSeconds
    $escapedDir = [System.Security.SecurityElement]::Escape($InstallDir)

    function badge($key) {
        $s = $Checklist[$key]
        if ($s -eq 'pass') { return '<span class="badge ok">OK</span>' }
        if ($s -eq 'warn') { return '<span class="badge warn">Warning</span>' }
        return '<span class="badge fail">Missing</span>'
    }

    $notes = ''
    if ($Checklist['npm'] -eq 'warn') {
        $notes += '<p class="note"><strong>Audio backend not built.</strong> Install Visual Studio Build Tools, or set <code>AUDIO_BACKEND=none</code> in <code>.env</code> for OBS scene switching only.</p>'
    }
    if ($Checklist['obs'] -eq 'warn') {
        $notes += '<p class="note">OBS is installed but double-check: <strong>Tools &rarr; WebSocket Server Settings &rarr; Enable</strong>.</p>'
    }
    if ($Checklist['env'] -eq 'warn') {
        $notes += '<p class="note"><strong>OBS password needed.</strong> Start the server, then open <code>http://localhost:3000/config.html</code> (or the gear icon in the app) and paste your OBS WebSocket password &mdash; found in OBS &rarr; Tools &rarr; WebSocket Server Settings.</p>'
    }

    $cardGit  = '<div class="card"><span class="label">Git</span>'         + (badge 'git')  + '</div>'
    $cardNode = '<div class="card"><span class="label">Node.js</span>'    + (badge 'node') + '</div>'
    $cardObs  = '<div class="card"><span class="label">OBS Studio</span>' + (badge 'obs')  + '</div>'
    $cardRepo = '<div class="card"><span class="label">Repository</span>' + (badge 'repo') + '</div>'
    $cardNpm  = '<div class="card"><span class="label">Packages</span>'   + (badge 'npm')  + '</div>'
    $cardEnv  = '<div class="card"><span class="label">Config</span>'     + (badge 'env')  + '</div>'
    $cards = "$cardGit`n$cardNode`n$cardObs`n$cardRepo`n$cardNpm`n$cardEnv"

    @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>jnk Live Assist &mdash; Setup Complete</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600&family=JetBrains+Mono:wght@400;500&display=swap" rel="stylesheet">
<script src="https://cdn.jsdelivr.net/npm/qrcode@1/build/qrcode.min.js"></script>
<style>
  :root { --bg:#0d1117; --surface:#161b22; --border:#30363d; --text:#e6edf3; --muted:#8b949e; --accent:#58a6ff; --green:#3fb950; --amber:#d29922; --red:#f85149; --r:10px; }
  * { box-sizing:border-box; margin:0; padding:0; }
  body { font-family:'Inter',sans-serif; background:var(--bg); color:var(--text); line-height:1.6; }

  main { max-width:640px; margin:0 auto; padding:48px 24px 40px; }

  h1 { font-size:1.6rem; font-weight:600; margin-bottom:4px; letter-spacing:-0.3px; }
  h1 span { color:var(--accent); }
  .sub { color:var(--muted); font-size:0.88rem; margin-bottom:4px; }
  .time { font-family:'JetBrains Mono',monospace; font-size:0.68rem; color:rgba(255,255,255,0.12); margin-bottom:28px; }

  .cards { display:grid; grid-template-columns:repeat(auto-fit, minmax(130px,1fr)); gap:8px; margin-bottom:12px; }
  .card { background:var(--surface); border:1px solid var(--border); border-radius:var(--r); padding:16px 12px; text-align:center; }
  .label { display:block; font-family:'JetBrains Mono',monospace; font-size:0.64rem; color:var(--muted); text-transform:uppercase; letter-spacing:0.3px; margin-bottom:7px; }
  .badge { display:inline-block; font-family:'JetBrains Mono',monospace; font-size:0.6rem; font-weight:600; padding:2px 7px; border-radius:var(--r); }
  .badge.ok   { background:rgba(63,185,80,0.1); color:var(--green); border:1px solid rgba(63,185,80,0.25); }
  .badge.warn { background:rgba(210,153,34,0.1); color:var(--amber); border:1px solid rgba(210,153,34,0.25); }
  .badge.fail { background:rgba(248,81,73,0.1); color:var(--red); border:1px solid rgba(248,81,73,0.3); }

  .notes { margin-bottom:32px; }
  .note { background:var(--surface); border:1px solid var(--border); border-left:3px solid var(--accent); border-radius:0 var(--r) var(--r) 0; padding:10px 14px; font-size:0.8rem; margin-bottom:6px; }
  .note code { background:rgba(88,166,255,0.08); padding:1px 4px; border-radius:4px; font-family:'JetBrains Mono',monospace; font-size:0.73rem; color:var(--accent); }

  .start { background:var(--surface); border:1px solid var(--border); border-radius:var(--r); padding:28px 24px; }
  .start h2 { font-size:1rem; font-weight:600; margin-bottom:14px; }
  .term { background:#0d1117; border:1px solid var(--border); border-radius:var(--r); padding:10px 14px; font-family:'JetBrains Mono',monospace; font-size:0.78rem; margin-bottom:7px; }
  .term .cmd { color:var(--text); }
  .term .cmt { display:block; color:rgba(255,255,255,0.12); font-size:0.66rem; margin-top:3px; }

  .url { text-align:center; margin-top:20px; }
  .url code { background:rgba(88,166,255,0.08); border:1px solid rgba(88,166,255,0.2); border-radius:var(--r); padding:6px 14px; font-family:'JetBrains Mono',monospace; font-size:0.82rem; color:var(--accent); }
  .url p { font-size:0.68rem; color:var(--muted); margin-top:6px; }

  .copy-wrap { text-align:center; margin-top:18px; }
  .copy-btn { font-family:'JetBrains Mono',monospace; font-size:0.76rem; font-weight:500; padding:9px 18px; border-radius:var(--r); border:none; background:var(--accent); color:#0d1117; cursor:pointer; transition:background 150ms; }
  .copy-btn:hover { background:#79c0ff; }

  .qr { text-align:center; margin-top:24px; }
  .qr canvas { border-radius:var(--r); }
  .qr p { font-size:0.66rem; color:var(--muted); margin-top:6px; }
  .config-link { text-align:center; margin-top:28px; font-size:0.78rem; color:var(--muted); }
  .config-link a { color:var(--accent); }

  footer { border-top:1px solid var(--border); padding:16px 24px; text-align:center; font-size:0.68rem; color:rgba(255,255,255,0.07); }
</style>
</head>
<body>

<main>
  <h1>Setup <span>complete</span></h1>
  <p class="sub">jnk Live Assist is installed. Control OBS scenes from your phone.</p>
  <p class="time">Finished in $elapsed seconds</p>

  <div class="cards">
$cards  </div>

  <div class="notes">
$notes  </div>

  <div class="start">
    <h2>Getting started</h2>

    <div class="term">
      <span class="cmd">cd "$escapedDir"</span>
    </div>
    <div class="term">
      <span class="cmd">.\start.bat</span>
      <span class="cmt"># starts the server and launches OBS</span>
    </div>

    <div class="term">
      <span class="cmd">node server.js</span>
      <span class="cmt"># server only, no OBS auto-launch</span>
    </div>

    <div class="url">
      <code>http://localhost:3000</code>
      <p>Open this on your phone once the server is running</p>
    </div>

    <div class="copy-wrap">
      <button class="copy-btn" onclick="navigator.clipboard.writeText('cd &quot;$escapedDir&quot; && .\\start.bat'); this.textContent='Copied'; setTimeout(()=>this.textContent='Copy command',1500);">Copy command</button>
    </div>

    <div class="qr">
      <canvas id="qrcode"></canvas>
      <p>Scan with your phone to open the control panel</p>
    </div>
  </div>

  <p class="config-link"><a href="http://localhost:3000/config.html">Open Settings</a> (server must be running) &mdash; change OBS password, audio channels, and more.</p>
</main>

<script>QRCode.toCanvas(document.getElementById('qrcode'),'http://localhost:3000',{width:160,margin:2,color:{dark:'#e6edf3',light:'#0d1117'}});</script>

<footer>jnk Live Assist &middot; <a href="https://github.com/jjannix/live-assist" style="color:var(--muted);text-decoration:none;">GitHub</a></footer>

</body>
</html>
"@ | Set-Content -Path $htmlFile -Encoding UTF8

    Write-Info 'Opening onboarding page ...'
    Start-Process $htmlFile
}

# =====================================================================
#  Main
# =====================================================================

Write-Banner

Write-Info "Install directory : $InstallDir"
Write-Info "Branch            : $Branch"
if ($winget) { Write-Info "winget            : available" } else { Write-Bang 'winget not found — automatic installs disabled' }
if ($Yes)    { Write-Info "Auto-mode         : on  ($env:JNK_YES=1)" }

# ---- Phase 1 --------------------------------------------------------
Write-Phase 1 'Checking tools'
if (-not (Ensure-Git))  { Die 'Git is required. Install it and re-run.' }
if (-not (Ensure-Node)) { Die 'Node.js is required. Install it and re-run.' }
$null = Ensure-OBS

# ---- Phase 2 --------------------------------------------------------
Write-Phase 2 'Downloading code'
Install-Repo

# ---- Phase 3 --------------------------------------------------------
Write-Phase 3 'Installing packages'
Install-Deps

# ---- Phase 4 --------------------------------------------------------
Write-Phase 4 'Configuration'
Bootstrap-Env

# ---- Phase 5 --------------------------------------------------------
Write-Phase 5 'Finishing up'
Write-Summary
