param(
    [string]$OutputDirectory = "",
    [string]$Context = "cloud-twin"
)

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path (Split-Path -Parent $PSScriptRoot) -Parent
if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path $projectRoot "data\osaka"
}

if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
    throw "kubectl is required to collect the Kubernetes configuration."
}

$collectionName = "collect-cloud-twin-{0}" -f (Get-Date -Format "ddMMyyyy_HHmmss")
$collectionDirectory = Join-Path $OutputDirectory $collectionName
$zipPath = Join-Path $OutputDirectory "$collectionName.zip"
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
New-Item -ItemType Directory -Force -Path $collectionDirectory | Out-Null

function Export-KubernetesJson {
    param(
        [string]$Name,
        [string[]]$Arguments
    )

    $json = & kubectl --context $Context @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Kubernetes collection failed: kubectl $($Arguments -join ' ')"
    }
    [System.IO.File]::WriteAllText(
        (Join-Path $collectionDirectory $Name),
        ($json -join [Environment]::NewLine),
        $utf8NoBom
    )
}

Export-KubernetesJson "nodes.json" @("get", "nodes", "-o", "json")
Export-KubernetesJson "pods.json" @("get", "pods", "-A", "-o", "json")
Export-KubernetesJson "clusterroles.json" @("get", "clusterroles", "-o", "json")
Export-KubernetesJson "roles.json" @("get", "roles", "-A", "-o", "json")
Export-KubernetesJson "clusterrolebindings.json" @("get", "clusterrolebindings", "-o", "json")
Export-KubernetesJson "rolebindings.json" @("get", "rolebindings", "-A", "-o", "json")
Export-KubernetesJson "services.json" @("get", "services", "-A", "-o", "json")

$secretsJson = & kubectl --context $Context get secrets -A -o json
if ($LASTEXITCODE -ne 0) {
    throw "Kubernetes Secret metadata collection failed."
}
$secrets = $secretsJson | ConvertFrom-Json
foreach ($secret in @($secrets.items)) {
    if ($secret.PSObject.Properties["data"]) {
        $secret.PSObject.Properties.Remove("data")
    }
}
[System.IO.File]::WriteAllText(
    (Join-Path $collectionDirectory "secrets.json"),
    ($secrets | ConvertTo-Json -Depth 100),
    $utf8NoBom
)

$python = (Get-Command python -ErrorAction Stop).Source
$zipScript = "import pathlib, sys, zipfile; root = pathlib.Path(sys.argv[1]); archive_path = pathlib.Path(sys.argv[2]); parent = root.parent; archive = zipfile.ZipFile(archive_path, 'w', zipfile.ZIP_DEFLATED); [archive.write(str(path), path.relative_to(parent).as_posix()) for path in root.rglob('*') if path.is_file()]; archive.close()"
& $python -c $zipScript $collectionDirectory $zipPath
if ($LASTEXITCODE -ne 0) {
    throw "Unable to create the OSAKA collection ZIP."
}
Remove-Item -LiteralPath $collectionDirectory -Recurse -Force

Write-Host "OSAKA collection created: $zipPath"
Write-Output $zipPath
