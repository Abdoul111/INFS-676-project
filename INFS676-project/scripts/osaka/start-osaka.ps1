param(
    [string]$OsakaDirectory = ""
)

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path (Split-Path -Parent $PSScriptRoot) -Parent
if (-not $OsakaDirectory) {
    $OsakaDirectory = Join-Path $projectRoot ".tools\osaka"
}

$installScript = Join-Path $PSScriptRoot "install-osaka.ps1"
if (-not (Test-Path (Join-Path $OsakaDirectory "compose.yml"))) {
    & powershell -ExecutionPolicy Bypass -File $installScript -OsakaDirectory $OsakaDirectory
    if ($LASTEXITCODE -ne 0) {
        throw "OSAKA installation failed."
    }
}

docker info 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "Docker is installed but the Docker daemon is unavailable. Start Docker Desktop and rerun this script."
}

$composeOverride = Join-Path $projectRoot "docker\docker-compose.osaka.override.yml"
if (-not (Test-Path $composeOverride)) {
    throw "OSAKA Compose override was not found: $composeOverride"
}

Push-Location $OsakaDirectory
try {
    & docker compose --env-file .env -f compose.yml -f $composeOverride build loader
    $buildExitCode = $LASTEXITCODE
    if ($buildExitCode -eq 0) {
        & docker compose --env-file .env -f compose.yml -f $composeOverride up -d
        $composeExitCode = $LASTEXITCODE
    }
    else {
        $composeExitCode = $buildExitCode
    }
}
finally {
    Pop-Location
}
if ($composeExitCode -ne 0) {
    throw "OSAKA Docker images failed to build or start."
}

$runningServices = @(
    docker compose --env-file (Join-Path $OsakaDirectory ".env") `
        -f (Join-Path $OsakaDirectory "compose.yml") `
        -f $composeOverride `
        ps --status running --services
)
if ($LASTEXITCODE -ne 0 -or $runningServices.Count -lt 4) {
    throw "OSAKA did not start all services. Running services: $($runningServices -join ', ')"
}

Write-Host "OSAKA is running:"
Write-Host "  Loader:     http://127.0.0.1:8080"
Write-Host "  Editor:     http://127.0.0.1:8081"
Write-Host "  Visualizer: http://127.0.0.1:8082"
