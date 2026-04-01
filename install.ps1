# ══════════════════════════════════════════════════════════════
#  Open Agents — One-Line Installer (Windows PowerShell)
#
#  Usage:
#    irm https://raw.githubusercontent.com/robit-man/oa-install/main/install.ps1 | iex
#
#  Requires: Docker Desktop for Windows (with WSL2 backend)
# ══════════════════════════════════════════════════════════════

$ErrorActionPreference = "Stop"

$OA_MODEL = if ($env:OA_MODEL) { $env:OA_MODEL } else { "qwen3:4b" }
$OA_VERSION = if ($env:OA_VERSION) { $env:OA_VERSION } else { "latest" }
$OA_WORKSPACE = if ($env:OA_WORKSPACE) { $env:OA_WORKSPACE } else { "$env:USERPROFILE\oa-workspace" }
$IMAGE_NAME = "open-agents"

Write-Host "`n  Open Agents - Docker Installer (Windows)" -ForegroundColor Cyan
Write-Host "  ========================================`n" -ForegroundColor Cyan

# ── Step 1: Check Docker CLI exists ──
try {
    $dockerVersion = (docker --version 2>&1) | Out-String
    Write-Host "Docker CLI: $($dockerVersion.Trim())" -ForegroundColor Green
} catch {
    Write-Host "ERROR: Docker Desktop is not installed." -ForegroundColor Red
    Write-Host ""
    Write-Host "Install Docker Desktop from:" -ForegroundColor Yellow
    Write-Host "  https://docs.docker.com/desktop/install/windows-install/" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "During installation, enable the WSL2 backend." -ForegroundColor Yellow
    Write-Host "After installing, restart your terminal and re-run this script."
    exit 1
}

# ── Step 2: Check Docker daemon is actually running ──
Write-Host "Checking Docker daemon..." -ForegroundColor Yellow
try {
    $info = docker info 2>&1 | Out-String
    if ($info -match "error|Cannot connect|pipe") {
        throw "Docker daemon not running"
    }
    Write-Host "Docker daemon: running" -ForegroundColor Green
} catch {
    Write-Host ""
    Write-Host "ERROR: Docker Desktop is installed but the Docker Engine is not running." -ForegroundColor Red
    Write-Host ""
    Write-Host "Fix:" -ForegroundColor Yellow
    Write-Host "  1. Open Docker Desktop from the Start Menu" -ForegroundColor White
    Write-Host "  2. Wait for the whale icon in the system tray to say 'Docker Desktop is running'" -ForegroundColor White
    Write-Host "  3. If it says 'starting...', wait 30-60 seconds for it to finish" -ForegroundColor White
    Write-Host "  4. Re-run this command:" -ForegroundColor White
    Write-Host "     irm https://raw.githubusercontent.com/robit-man/oa-install/main/install.ps1 | iex" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "If Docker Desktop won't start:" -ForegroundColor Yellow
    Write-Host "  - Open PowerShell as Administrator and run: wsl --update" -ForegroundColor White
    Write-Host "  - Ensure WSL2 is enabled: wsl --set-default-version 2" -ForegroundColor White
    Write-Host "  - Restart your computer, then try again" -ForegroundColor White
    Write-Host ""

    # Try to auto-start Docker Desktop
    $dockerDesktop = "${env:ProgramFiles}\Docker\Docker\Docker Desktop.exe"
    if (Test-Path $dockerDesktop) {
        Write-Host "Attempting to start Docker Desktop..." -ForegroundColor Yellow
        Start-Process $dockerDesktop
        Write-Host "Docker Desktop is starting. Wait for it to finish, then re-run this script." -ForegroundColor Yellow
    }
    exit 1
}

# ── Step 3: Check NVIDIA GPU ──
$GPU_FLAGS = ""
try {
    $gpuName = (nvidia-smi --query-gpu=name --format=csv,noheader 2>$null) | Select-Object -First 1
    if ($gpuName) {
        Write-Host "GPU: $gpuName" -ForegroundColor Green
        $GPU_FLAGS = "--gpus all"
    } else {
        Write-Host "GPU: not detected (CPU-only mode)" -ForegroundColor Yellow
    }
} catch {
    Write-Host "GPU: not detected (CPU-only mode)" -ForegroundColor Yellow
}

# ── Step 4: Create workspace ──
New-Item -ItemType Directory -Path $OA_WORKSPACE -Force | Out-Null
Write-Host "Workspace: $OA_WORKSPACE" -ForegroundColor Green

# ── Step 5: Download build files ──
Write-Host "`nDownloading build files..." -ForegroundColor Cyan
$tmpDir = Join-Path $env:TEMP "oa-install-$(Get-Date -Format 'yyyyMMddHHmmss')"
New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
$repoUrl = "https://raw.githubusercontent.com/robit-man/oa-install/main"

try {
    Invoke-WebRequest -Uri "$repoUrl/Dockerfile" -OutFile "$tmpDir\Dockerfile" -UseBasicParsing
    Invoke-WebRequest -Uri "$repoUrl/entrypoint.sh" -OutFile "$tmpDir\entrypoint.sh" -UseBasicParsing
} catch {
    Write-Host "ERROR: Failed to download build files." -ForegroundColor Red
    Write-Host "Check your internet connection and try again." -ForegroundColor Yellow
    Remove-Item -Recurse -Force $tmpDir -ErrorAction SilentlyContinue
    exit 1
}

# ── Step 6: Build Docker image ──
Write-Host "Building OA Docker image (this may take 2-5 minutes on first run)..." -ForegroundColor Cyan
try {
    docker build --build-arg OA_VERSION=$OA_VERSION -t $IMAGE_NAME "$tmpDir"
    if ($LASTEXITCODE -ne 0) { throw "Docker build failed with exit code $LASTEXITCODE" }
    Write-Host "Docker image built successfully." -ForegroundColor Green
} catch {
    Write-Host ""
    Write-Host "ERROR: Docker build failed." -ForegroundColor Red
    Write-Host ""
    Write-Host "Common fixes:" -ForegroundColor Yellow
    Write-Host "  1. Make sure Docker Desktop is fully started (whale icon = steady, not animating)" -ForegroundColor White
    Write-Host "  2. In Docker Desktop Settings > General, ensure 'Use the WSL 2 based engine' is checked" -ForegroundColor White
    Write-Host "  3. In Docker Desktop Settings > Resources > WSL Integration, enable your distro" -ForegroundColor White
    Write-Host "  4. Try: docker run hello-world (if this fails, Docker itself has an issue)" -ForegroundColor White
    Write-Host ""
    Remove-Item -Recurse -Force $tmpDir -ErrorAction SilentlyContinue
    exit 1
}
Remove-Item -Recurse -Force $tmpDir -ErrorAction SilentlyContinue

# ── Step 7: Create launcher ──
$launcherDir = "$env:USERPROFILE\.local\bin"
New-Item -ItemType Directory -Path $launcherDir -Force | Out-Null
$launcherPath = "$launcherDir\oa-docker.cmd"

@"
@echo off
set IMAGE_NAME=open-agents
set CONTAINER_NAME=oa
if "%OA_WORKSPACE%"=="" set OA_WORKSPACE=%USERPROFILE%\oa-workspace
if "%OA_MODEL%"=="" set OA_MODEL=qwen3:4b

REM Stop existing container if running
docker rm -f %CONTAINER_NAME% >nul 2>&1

REM Detect GPU
set GPU_FLAGS=
nvidia-smi >nul 2>&1 && set GPU_FLAGS=--gpus all

REM Launch container
docker run -it --rm --name %CONTAINER_NAME% %GPU_FLAGS% -p 11434:11434 -p 11435:11435 -e OA_MODEL=%OA_MODEL% -e TERM=xterm-256color -e COLORTERM=truecolor -v %OA_WORKSPACE%:/workspace -v %USERPROFILE%\.ollama:/root/.ollama -v %USERPROFILE%\.open-agents:/root/.open-agents %IMAGE_NAME% %*
"@ | Out-File -Encoding ASCII $launcherPath

# ── Step 8: Add to PATH ──
$currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($currentPath -notlike "*$launcherDir*") {
    [Environment]::SetEnvironmentVariable("Path", "$launcherDir;$currentPath", "User")
    $env:Path = "$launcherDir;$env:Path"
    Write-Host "Added $launcherDir to PATH" -ForegroundColor Green
}

# ── Step 9: Success! ──
Write-Host ""
Write-Host "  Installation Complete!" -ForegroundColor Green
Write-Host "  =====================" -ForegroundColor Green
Write-Host ""
Write-Host "  Launch OA:   oa-docker" -ForegroundColor Cyan
Write-Host "  API mode:    oa-docker oa serve" -ForegroundColor Cyan
Write-Host "  Shell:       oa-docker bash" -ForegroundColor Cyan
Write-Host "  Workspace:   $OA_WORKSPACE" -ForegroundColor Cyan
Write-Host ""

# ── Step 10: Launch ──
Write-Host "Starting OA..." -ForegroundColor Yellow
& $launcherPath
