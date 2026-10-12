$ErrorActionPreference = "Stop"

$projectRoot = Split-Path (Split-Path -Parent $PSScriptRoot) -Parent
$graphPath = Join-Path $projectRoot "data\graph\attack-graph.json"

if (-not (Test-Path $graphPath)) {
    throw "Attack graph was not found. Run run-data-pipeline.ps1 first."
}

$graph = Get-Content -Raw $graphPath | ConvertFrom-Json
$paths = @($graph.predictedPaths)

function Assert-Path {
    param(
        [string]$Name,
        [string[]]$RequiredNodes
    )

    $match = $paths | Where-Object {
        $pathNodes = @($_.nodes)
        ($RequiredNodes | Where-Object { $pathNodes -notcontains $_ }).Count -eq 0
    }

    if (-not $match) {
        throw "Expected attack path was not found: $Name"
    }
    Write-Host "PASS: $Name"
}

Assert-Path "web workload reaches public object" @(
    "workload:web-pod",
    "iam-role:arn:aws:iam::000000000000:role/cloud-twin-web-role",
    "s3-object:cloud-twin-public/public-object.txt"
)

Assert-Path "web workload can reach API role through role assumption" @(
    "workload:web-pod",
    "iam-role:arn:aws:iam::000000000000:role/cloud-twin-web-role",
    "iam-role:arn:aws:iam::000000000000:role/cloud-twin-api-role"
)

Assert-Path "web workload reaches sensitive object through API role" @(
    "workload:web-pod",
    "iam-role:arn:aws:iam::000000000000:role/cloud-twin-web-role",
    "iam-role:arn:aws:iam::000000000000:role/cloud-twin-api-role",
    "s3-object:cloud-twin-sensitive/sensitive-object.txt"
)

Write-Host "Validated $($paths.Count) unique predicted paths."
