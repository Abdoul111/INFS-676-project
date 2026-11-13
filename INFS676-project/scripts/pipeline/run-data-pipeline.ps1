$ErrorActionPreference = "Stop"

$projectRoot = Split-Path (Split-Path -Parent $PSScriptRoot) -Parent
$collector = Join-Path $PSScriptRoot "collect-localstack-state.ps1"
$kubernetesCollector = Join-Path $PSScriptRoot "collect-kubernetes-state.ps1"
$graphBuilder = Join-Path $PSScriptRoot "build-attack-graph.py"
$statePath = Join-Path $projectRoot "data\raw\localstack-state.json"
$kubernetesStatePath = Join-Path $projectRoot "data\raw\kubernetes-state.json"
$graphPath = Join-Path $projectRoot "data\graph\attack-graph.json"
$python = (Get-Command python -ErrorAction Stop).Source

powershell -ExecutionPolicy Bypass -File $collector
if ($LASTEXITCODE -ne 0) {
    throw "LocalStack collection failed."
}

powershell -ExecutionPolicy Bypass -File $kubernetesCollector
if ($LASTEXITCODE -ne 0) {
    throw "Kubernetes collection failed."
}

& $python $graphBuilder $statePath --kubernetes-state $kubernetesStatePath --output $graphPath
if ($LASTEXITCODE -ne 0) {
    throw "Attack graph construction failed."
}

Write-Host "Data pipeline complete."
Write-Host "Raw state: $statePath"
Write-Host "Graph: $graphPath"
