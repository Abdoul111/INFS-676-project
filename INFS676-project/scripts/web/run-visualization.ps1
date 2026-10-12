$ErrorActionPreference = "Stop"

$projectRoot = Split-Path (Split-Path -Parent $PSScriptRoot) -Parent
$python = (Get-Command python -ErrorAction Stop).Source
$app = Join-Path $projectRoot "web\app.py"

Write-Host "Starting the graph visualization at http://127.0.0.1:5000"
& $python $app
