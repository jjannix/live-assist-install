# jnk Live Assist — one-shot installer for Windows
# Run in PowerShell:
#   Set-ExecutionPolicy Bypass -Scope Process -Force
#   .\install.ps1

$ErrorActionPreference = "Stop"
$Repo = "https://github.com/jjannix/live-assist.git"
$Dest = "$env:USERPROFILE\Documents\live-assist"

# ── Git ────────────────────────────────────────────────────────
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "Git not found — installing via winget..." -ForegroundColor Yellow
    winget install --id Git.Git --accept-source-agreements --accept-package-agreements
    refreshenv 2>$null
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Host "ERROR: git still not on PATH. Restart your terminal and try again." -ForegroundColor Red
        exit 1
    }
}

# ── Clone ──────────────────────────────────────────────────────
if (Test-Path $Dest) {
    Write-Host "Found existing install at $Dest — pulling latest..." -ForegroundColor Cyan
    Push-Location $Dest
    git pull origin main
    Pop-Location
} else {
    Write-Host "Cloning jnk Live Assist into $Dest..." -ForegroundColor Cyan
    git clone $Repo $Dest
}

# ── Node.js (x64 required) ────────────────────────────────────
$nodeExe = $null
if (Test-Path "C:\Program Files\nodejs\node.exe") {
    $nodeExe = "C:\Program Files\nodejs\node.exe"
}
if (-not $nodeExe) {
    $nodeExe = (Get-Command node -ErrorAction SilentlyContinue).Source
}
if (-not $nodeExe) {
    Write-Host "Node.js not found — installing via winget..." -ForegroundColor Yellow
    winget install --id OpenJS.NodeJS.LTS --accept-source-agreements --accept-package-agreements
    refreshenv 2>$null
    $nodeExe = (Get-Command node -ErrorAction SilentlyContinue).Source
    if (-not $nodeExe) {
        Write-Host "ERROR: Node.js still not found. Restart your terminal and try again." -ForegroundColor Red
        exit 1
    }
}

$arch = & $nodeExe -e "console.log(process.arch)"
Write-Host "Node: $nodeExe (arch: $arch)" -ForegroundColor Gray
if ($arch -ne "x64" -and $arch -ne "ia32") {
    Write-Host "WARNING: Node is $arch, but native-sound-mixer requires x64." -ForegroundColor Yellow
    Write-Host "Install x64 Node from https://nodejs.org/ and re-run." -ForegroundColor Yellow
}

# ── npm install ────────────────────────────────────────────────
Write-Host "Installing dependencies..." -ForegroundColor Cyan
Push-Location $Dest
& $nodeExe "$((Get-Command npm).Source)\..\..\node_modules\npm\bin\npm-cli.js" install
Pop-Location

# ── .env ───────────────────────────────────────────────────────
$envFile = Join-Path $Dest ".env"
$envExample = Join-Path $Dest ".env.example"
if (-not (Test-Path $envFile) -and (Test-Path $envExample)) {
    Copy-Item $envExample $envFile
    Write-Host ""
    Write-Host "Created .env from .env.example" -ForegroundColor Green
    Write-Host ">>> Edit $envFile and set your OBS_WEBSOCKET_PASSWORD before starting." -ForegroundColor Yellow
    Write-Host ""
} elseif (Test-Path $envFile) {
    Write-Host ".env already exists — leaving it untouched." -ForegroundColor Gray
}

# ── Done ───────────────────────────────────────────────────────
Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "  jnk Live Assist installed successfully!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host ""
Write-Host "To start:" -ForegroundColor Cyan
Write-Host "  cd $Dest" -ForegroundColor White
Write-Host "  .\start.bat" -ForegroundColor White
Write-Host ""
Write-Host "Then open http://localhost:3000 on your phone." -ForegroundColor Cyan
