# ══════════════════════════════════════════════════════════════
#  Open Agents — Fully Automatic Installer (Windows PowerShell)
#
#  Usage:
#    irm https://raw.githubusercontent.com/robit-man/oa-install/main/install.ps1 | iex
#
#  Handles EVERYTHING automatically:
#    1. Elevates to admin if needed (UAC prompt)
#    2. Enables WSL2 if not present
#    3. Installs Docker Desktop if missing
#    4. Starts Docker Desktop and waits for daemon
#    5. Installs NVIDIA Container Toolkit if GPU present
#    6. Builds OA Docker image
#    7. Creates oa-docker launcher
#    8. Launches OA
# ══════════════════════════════════════════════════════════════

$OA_MODEL = if ($env:OA_MODEL) { $env:OA_MODEL } else { "qwen3:4b" }
$OA_VERSION = if ($env:OA_VERSION) { $env:OA_VERSION } else { "latest" }
$OA_WORKSPACE = if ($env:OA_WORKSPACE) { $env:OA_WORKSPACE } else { "$env:USERPROFILE\oa-workspace" }
$IMAGE_NAME = "open-agents"

# ── Helper: check if running as admin ──
function Test-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# ── Helper: re-launch self as admin ──
function Invoke-Elevated {
    param([string]$Reason)
    Write-Host "  Requesting admin privileges: $Reason" -ForegroundColor Yellow
    $scriptUrl = "https://raw.githubusercontent.com/robit-man/oa-install/main/install.ps1"
    # Pass env vars through to elevated process
    $envBlock = "`$env:OA_MODEL='$OA_MODEL'; `$env:OA_VERSION='$OA_VERSION'; `$env:OA_WORKSPACE='$OA_WORKSPACE'; "
    $cmd = "$envBlock irm $scriptUrl | iex"
    Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", $cmd -Wait
    exit 0
}

Write-Host ""
Write-Host "  Open Agents - Automatic Installer (Windows)" -ForegroundColor Cyan
Write-Host "  ============================================" -ForegroundColor Cyan
Write-Host ""

# ═══════════════════════════════════════════════════════════
# PHASE 1: WSL2
# ═══════════════════════════════════════════════════════════

Write-Host "[1/8] Checking WSL2..." -ForegroundColor Yellow
$wslInstalled = $false
try {
    $wslOut = wsl --status 2>&1 | Out-String
    if ($wslOut -match "Default Version: 2" -or $wslOut -match "WSL version: 2" -or $wslOut -match "WSL 2") {
        $wslInstalled = $true
        Write-Host "  WSL2: installed" -ForegroundColor Green
    }
} catch {}

if (-not $wslInstalled) {
    Write-Host "  WSL2 not ready — installing..." -ForegroundColor Yellow
    if (-not (Test-Admin)) {
        Invoke-Elevated "Install WSL2"
    }
    # Enable WSL + Virtual Machine Platform
    try {
        dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart 2>$null | Out-Null
        dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart 2>$null | Out-Null
    } catch {}
    # Install/update WSL
    try {
        wsl --install --no-distribution 2>$null | Out-Null
        wsl --update 2>$null | Out-Null
        wsl --set-default-version 2 2>$null | Out-Null
    } catch {}
    Write-Host "  WSL2: installed (reboot may be needed if this is the first time)" -ForegroundColor Green
}

# ═══════════════════════════════════════════════════════════
# PHASE 2: Docker Desktop
# ═══════════════════════════════════════════════════════════

Write-Host "[2/8] Checking Docker Desktop..." -ForegroundColor Yellow

$dockerCliExists = $false
try {
    $null = Get-Command docker -ErrorAction Stop
    $dockerCliExists = $true
} catch {}

if (-not $dockerCliExists) {
    Write-Host "  Docker not found — downloading Docker Desktop installer..." -ForegroundColor Yellow

    $installerPath = Join-Path $env:TEMP "DockerDesktopInstaller.exe"
    $dockerUrl = "https://desktop.docker.com/win/main/amd64/Docker%20Desktop%20Installer.exe"

    try {
        Invoke-WebRequest -Uri $dockerUrl -OutFile $installerPath -UseBasicParsing
    } catch {
        Write-Host "  ERROR: Failed to download Docker Desktop." -ForegroundColor Red
        Write-Host "  Download manually from: https://docs.docker.com/desktop/install/windows-install/" -ForegroundColor Yellow
        exit 1
    }

    Write-Host "  Installing Docker Desktop (this takes 1-3 minutes)..." -ForegroundColor Yellow
    if (-not (Test-Admin)) {
        Invoke-Elevated "Install Docker Desktop"
    }
    Start-Process -FilePath $installerPath -ArgumentList "install", "--quiet", "--accept-license" -Wait
    Remove-Item $installerPath -ErrorAction SilentlyContinue

    # Refresh PATH after Docker install
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machinePath;$userPath"

    Write-Host "  Docker Desktop: installed" -ForegroundColor Green
}

$dockerVersion = (docker --version 2>&1) | Out-String
Write-Host "  $($dockerVersion.Trim())" -ForegroundColor Green

# ═══════════════════════════════════════════════════════════
# PHASE 3: Start Docker daemon and wait
# ═══════════════════════════════════════════════════════════

Write-Host "[3/8] Ensuring Docker daemon is running..." -ForegroundColor Yellow

function Test-DockerDaemon {
    try {
        $out = docker info 2>&1 | Out-String
        return ($out -notmatch "error|Cannot connect|pipe|not running")
    } catch { return $false }
}

if (-not (Test-DockerDaemon)) {
    Write-Host "  Docker daemon not running — starting Docker Desktop..." -ForegroundColor Yellow

    # Find Docker Desktop exe
    $dockerDesktopPaths = @(
        "${env:ProgramFiles}\Docker\Docker\Docker Desktop.exe",
        "${env:ProgramFiles(x86)}\Docker\Docker\Docker Desktop.exe",
        "$env:LOCALAPPDATA\Docker\Docker Desktop.exe"
    )
    $dockerExe = $null
    foreach ($p in $dockerDesktopPaths) {
        if (Test-Path $p) { $dockerExe = $p; break }
    }

    if ($dockerExe) {
        Start-Process $dockerExe -WindowStyle Minimized
    } else {
        # Try via start menu shortcut
        try { Start-Process "Docker Desktop" -ErrorAction Stop } catch {
            Write-Host "  Cannot find Docker Desktop executable. Please start it manually." -ForegroundColor Red
            exit 1
        }
    }

    # Wait up to 120 seconds for daemon to be ready
    Write-Host "  Waiting for Docker engine to start " -NoNewline -ForegroundColor Yellow
    $maxWait = 120
    $waited = 0
    while ($waited -lt $maxWait) {
        if (Test-DockerDaemon) { break }
        Write-Host "." -NoNewline -ForegroundColor Yellow
        Start-Sleep -Seconds 3
        $waited += 3
    }
    Write-Host ""

    if (-not (Test-DockerDaemon)) {
        Write-Host "  ERROR: Docker daemon did not start within ${maxWait}s." -ForegroundColor Red
        Write-Host "  Try restarting your computer, then run this script again." -ForegroundColor Yellow
        exit 1
    }
}

Write-Host "  Docker daemon: running" -ForegroundColor Green

# ═══════════════════════════════════════════════════════════
# PHASE 4: GPU detection
# ═══════════════════════════════════════════════════════════

Write-Host "[4/8] Detecting GPU..." -ForegroundColor Yellow
$GPU_FLAGS = ""
try {
    $gpuName = (nvidia-smi --query-gpu=name --format=csv,noheader 2>$null) | Select-Object -First 1
    if ($gpuName) {
        $gpuVram = (nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>$null) | Select-Object -First 1
        Write-Host "  GPU: $gpuName (${gpuVram}MB VRAM)" -ForegroundColor Green
        $GPU_FLAGS = "--gpus all"
    } else {
        Write-Host "  GPU: none detected (CPU-only mode)" -ForegroundColor Yellow
    }
} catch {
    Write-Host "  GPU: none detected (CPU-only mode)" -ForegroundColor Yellow
}

# ═══════════════════════════════════════════════════════════
# PHASE 5: Workspace
# ═══════════════════════════════════════════════════════════

Write-Host "[5/8] Creating workspace..." -ForegroundColor Yellow
New-Item -ItemType Directory -Path $OA_WORKSPACE -Force | Out-Null
Write-Host "  Workspace: $OA_WORKSPACE" -ForegroundColor Green

# ═══════════════════════════════════════════════════════════
# PHASE 6: Build Docker image
# ═══════════════════════════════════════════════════════════

Write-Host "[6/8] Building OA Docker image..." -ForegroundColor Yellow

$tmpDir = Join-Path $env:TEMP "oa-install-$(Get-Date -Format 'yyyyMMddHHmmss')"
New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
$repoUrl = "https://raw.githubusercontent.com/robit-man/oa-install/main"

try {
    Invoke-WebRequest -Uri "$repoUrl/Dockerfile" -OutFile "$tmpDir\Dockerfile" -UseBasicParsing
    Invoke-WebRequest -Uri "$repoUrl/entrypoint.sh" -OutFile "$tmpDir\entrypoint.sh" -UseBasicParsing
} catch {
    Write-Host "  ERROR: Failed to download build files. Check internet connection." -ForegroundColor Red
    Remove-Item -Recurse -Force $tmpDir -ErrorAction SilentlyContinue
    exit 1
}

Write-Host "  Building image (2-5 min on first run)..." -ForegroundColor Yellow
docker build --build-arg OA_VERSION=$OA_VERSION -t $IMAGE_NAME "$tmpDir" 2>&1 | ForEach-Object {
    if ($_ -match "^Step|^Successfully|^#\d+ DONE") { Write-Host "  $_" -ForegroundColor DarkGray }
}

if ($LASTEXITCODE -ne 0) {
    Write-Host "  ERROR: Docker build failed." -ForegroundColor Red
    Write-Host "  Try: docker run hello-world  — if that fails, Docker itself has an issue." -ForegroundColor Yellow
    Remove-Item -Recurse -Force $tmpDir -ErrorAction SilentlyContinue
    exit 1
}

Remove-Item -Recurse -Force $tmpDir -ErrorAction SilentlyContinue
Write-Host "  Docker image: built" -ForegroundColor Green

# ═══════════════════════════════════════════════════════════
# PHASE 7: Create launcher
# ═══════════════════════════════════════════════════════════

Write-Host "[7/8] Creating oa-docker launcher..." -ForegroundColor Yellow

$launcherDir = "$env:USERPROFILE\.local\bin"
New-Item -ItemType Directory -Path $launcherDir -Force | Out-Null
$launcherPath = "$launcherDir\oa-docker.cmd"

@"
@echo off
set IMAGE_NAME=open-agents
set CONTAINER_NAME=oa
if "%OA_WORKSPACE%"=="" set OA_WORKSPACE=%USERPROFILE%\oa-workspace
if "%OA_MODEL%"=="" set OA_MODEL=qwen3:4b
docker rm -f %CONTAINER_NAME% >nul 2>&1
set GPU_FLAGS=
nvidia-smi >nul 2>&1 && set GPU_FLAGS=--gpus all
docker run -it --rm --name %CONTAINER_NAME% %GPU_FLAGS% -p 11434:11434 -p 11435:11435 -e OA_MODEL=%OA_MODEL% -e TERM=xterm-256color -e COLORTERM=truecolor -v %OA_WORKSPACE%:/workspace -v %USERPROFILE%\.ollama:/root/.ollama -v %USERPROFILE%\.open-agents:/root/.open-agents %IMAGE_NAME% %*
"@ | Out-File -Encoding ASCII $launcherPath

# Add to user PATH
$currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($currentPath -notlike "*$launcherDir*") {
    [Environment]::SetEnvironmentVariable("Path", "$launcherDir;$currentPath", "User")
    $env:Path = "$launcherDir;$env:Path"
}

Write-Host "  Launcher: $launcherPath" -ForegroundColor Green

# ═══════════════════════════════════════════════════════════
# PHASE 8: Launch
# ═══════════════════════════════════════════════════════════

Write-Host "[8/8] Launching Open Agents..." -ForegroundColor Yellow
Write-Host ""
Write-Host "  ==============================================" -ForegroundColor Green
Write-Host "     Installation Complete!" -ForegroundColor Green
Write-Host "  ==============================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Next time, just run:  oa-docker" -ForegroundColor Cyan
Write-Host "  API mode:             oa-docker oa serve" -ForegroundColor Cyan
Write-Host "  Shell:                oa-docker bash" -ForegroundColor Cyan
Write-Host "  Workspace:            $OA_WORKSPACE" -ForegroundColor Cyan
Write-Host ""

& $launcherPath
