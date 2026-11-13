param(
    [string]$OsakaDirectory = "",
    [string]$HostIp = "",
    [string]$Neo4jPassword = ""
)

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path (Split-Path -Parent $PSScriptRoot) -Parent
if (-not $OsakaDirectory) {
    $OsakaDirectory = Join-Path $projectRoot ".tools\osaka"
}

$repository = "https://github.com/ANSSI-FR/OSAKA.git"
$revision = "c8fa91591888db2999b3f9b38164c0c12a483117"

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw "git is required to install OSAKA."
}
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw "Docker is required to install OSAKA."
}

if (Test-Path $OsakaDirectory) {
    if (-not (Test-Path (Join-Path $OsakaDirectory ".git"))) {
        throw "The OSAKA directory exists but is not a git checkout: $OsakaDirectory"
    }
    & git -C $OsakaDirectory fetch --depth 1 origin main
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to update the OSAKA checkout."
    }
}
else {
    $parent = Split-Path $OsakaDirectory -Parent
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    & git clone --no-checkout $repository $OsakaDirectory
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to clone OSAKA."
    }
}

& git -C $OsakaDirectory checkout --force $revision
if ($LASTEXITCODE -ne 0) {
    throw "Unable to check out the pinned OSAKA revision $revision."
}

if (-not $HostIp) {
    $HostIp = $env:OSAKA_HOST_IP
}
if (-not $HostIp) {
    $HostIp = "172.29.0.20"
}
if (-not $Neo4jPassword) {
    $Neo4jPassword = $env:OSAKA_NEO4J_PASSWORD
}
if (-not $Neo4jPassword) {
    $Neo4jPassword = "OsakaLocalOnly-ChangeMe"
}

@"
HOST_IP=$HostIp
NEO4J_PASSWORD=$Neo4jPassword
"@ | Set-Content -Path (Join-Path $OsakaDirectory ".env") -Encoding ascii

@"
NEO4J_URI=bolt://172.29.0.20:7687
NEO4J_USER=neo4j
NEO4J_PASSWORD=$Neo4jPassword
NEO4J_VERSION=4
NEO4J_DATABASE=neo4j
"@ | Set-Content -Path (Join-Path $OsakaDirectory "sources\.env") -Encoding ascii

Write-Host "OSAKA installed at $OsakaDirectory"
Write-Host "Pinned revision: $revision"
Write-Host "Neo4j password configured in local OSAKA environment files."
