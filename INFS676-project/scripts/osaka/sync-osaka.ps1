param(
    [string]$Context = "cloud-twin",
    [string]$Neo4jPassword = "",
    [switch]$RefreshEnvironment,
    [string]$ExistingCollectionPath = ""
)

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path (Split-Path -Parent $PSScriptRoot) -Parent
$startScript = Join-Path $PSScriptRoot "start-osaka.ps1"
$environmentScript = Join-Path $projectRoot "scripts\environment\start-environment.ps1"
$collectScript = Join-Path $PSScriptRoot "collect-osaka.ps1"
$uploadScript = Join-Path $PSScriptRoot "upload-osaka-collection.ps1"
$importScript = Join-Path $PSScriptRoot "import-attack-graph.py"
$publishScript = Join-Path $PSScriptRoot "publish-project-dashboard.py"
$graphPath = Join-Path $projectRoot "data\graph\attack-graph.json"
$catalogPath = Join-Path $projectRoot "data\catalog\vulnerability-catalog.json"
$dashboardPath = Join-Path $projectRoot "integrations\osaka\project-dashboard.json"
$python = (Get-Command python -ErrorAction Stop).Source

if (-not $Neo4jPassword) {
    $Neo4jPassword = $env:OSAKA_NEO4J_PASSWORD
}
if (-not $Neo4jPassword) {
    $Neo4jPassword = "OsakaLocalOnly-ChangeMe"
}

& powershell -ExecutionPolicy Bypass -File $startScript
if ($LASTEXITCODE -ne 0) {
    throw "OSAKA startup failed."
}

if (-not (Test-Path $graphPath)) {
    throw "Existing graph not found: $graphPath. Run with -RefreshEnvironment first."
}

if (-not (Test-Path $catalogPath)) {
    throw "Vulnerability catalog not found: $catalogPath."
}

if ($RefreshEnvironment) {
    & powershell -ExecutionPolicy Bypass -File $environmentScript
    if ($LASTEXITCODE -ne 0) {
        throw "Cloud Twin environment and graph pipeline failed."
    }

    $collectionPath = & powershell -ExecutionPolicy Bypass -File $collectScript -Context $Context |
        Select-Object -Last 1
    if ($LASTEXITCODE -ne 0) {
        throw "OSAKA Kubernetes collection failed."
    }

    & powershell -ExecutionPolicy Bypass -File $uploadScript -CollectionPath $collectionPath
    if ($LASTEXITCODE -ne 0) {
        throw "OSAKA collection upload failed."
    }
}
elseif ($ExistingCollectionPath) {
    & powershell -ExecutionPolicy Bypass -File $uploadScript -CollectionPath $ExistingCollectionPath
    if ($LASTEXITCODE -ne 0) {
        throw "OSAKA collection upload failed."
    }
}
else {
    Write-Host "Using existing JSON graph and current OSAKA Kubernetes database."
    Write-Host "Use -RefreshEnvironment to recollect LocalStack and Kubernetes state."
}

& $python $importScript $graphPath --catalog $catalogPath --password $Neo4jPassword
if ($LASTEXITCODE -ne 0) {
    throw "Unified graph import failed."
}

& $python $publishScript $dashboardPath --password $Neo4jPassword
if ($LASTEXITCODE -ne 0) {
    throw "Project dashboard publication failed."
}

Write-Host "Unified OSAKA sync complete."
Write-Host "Dashboard: http://127.0.0.1:8082"
