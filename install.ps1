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

# Check Docker
try {
    $dockerVersion = docker --version
    Write-Host "Docker: $dockerVersion" -ForegroundColor Green
} catch {
    Write-Host "Docker Desktop is required." -ForegroundColor Red
    Write-Host "Download from: https://docs.docker.com/desktop/install/windows-install/"
    Write-Host "Enable WSL2 backend during installation."
    exit 1
}

# Check NVIDIA GPU
$GPU_FLAGS = ""
try {
    $gpuName = nvidia-smi --query-gpu=name --format=csv,noheader 2>$null | Select-Object -First 1
    if ($gpuName) {
        Write-Host "GPU: $gpuName" -ForegroundColor Green
        $GPU_FLAGS = "--gpus all"
    }
} catch {
    Write-Host "GPU: not detected (CPU-only)" -ForegroundColor Yellow
}

# Create workspace
New-Item -ItemType Directory -Path $OA_WORKSPACE -Force | Out-Null
Write-Host "Workspace: $OA_WORKSPACE" -ForegroundColor Green

# Download build files
$tmpDir = New-TemporaryFile | ForEach-Object { Remove-Item $_; New-Item -ItemType Directory -Path $_ }
$repoUrl = "https://raw.githubusercontent.com/robit-man/oa-install/main"

Invoke-WebRequest -Uri "$repoUrl/Dockerfile" -OutFile "$tmpDir\Dockerfile"
Invoke-WebRequest -Uri "$repoUrl/entrypoint.sh" -OutFile "$tmpDir\entrypoint.sh"

# Build image
Write-Host "`nBuilding OA Docker image..." -ForegroundColor Cyan
docker build --build-arg OA_VERSION=$OA_VERSION -t $IMAGE_NAME "$tmpDir"
Remove-Item -Recurse -Force $tmpDir

# Create launcher batch file
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

docker run -it --rm --name %CONTAINER_NAME% %GPU_FLAGS% --network host -e OA_MODEL=%OA_MODEL% -e TERM=xterm-256color -v %OA_WORKSPACE%:/workspace -v %USERPROFILE%\.ollama:/root/.ollama -v %USERPROFILE%\.open-agents:/root/.open-agents %IMAGE_NAME% %*
"@ | Out-File -Encoding ASCII $launcherPath

# Add to PATH
$currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($currentPath -notlike "*$launcherDir*") {
    [Environment]::SetEnvironmentVariable("Path", "$launcherDir;$currentPath", "User")
    $env:Path = "$launcherDir;$env:Path"
}

Write-Host "`n  Installation Complete!" -ForegroundColor Green
Write-Host "  Launch:    oa-docker" -ForegroundColor Cyan
Write-Host "  API mode:  oa-docker oa serve" -ForegroundColor Cyan
Write-Host "  Shell:     oa-docker bash" -ForegroundColor Cyan
Write-Host "  Workspace: $OA_WORKSPACE`n" -ForegroundColor Cyan

# Launch
& $launcherPath
