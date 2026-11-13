param(
    [string]$OsakaDirectory = ""
)

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path (Split-Path -Parent $PSScriptRoot) -Parent
if (-not $OsakaDirectory) {
    $OsakaDirectory = Join-Path $projectRoot ".tools\osaka"
}

if (-not (Test-Path (Join-Path $OsakaDirectory "compose.yml"))) {
    Write-Host "OSAKA is not installed."
    exit 0
}

Push-Location $OsakaDirectory
try {
    & docker compose --env-file .env -f compose.yml down
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to stop OSAKA."
    }
}
finally {
    Pop-Location
}
