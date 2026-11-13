param(
    [string]$CollectionPath = "",
    [string]$LoaderUrl = "http://127.0.0.1:8080"
)

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path (Split-Path -Parent $PSScriptRoot) -Parent
if (-not $CollectionPath) {
    $collection = Get-ChildItem (Join-Path $projectRoot "data\osaka") -Filter "collect-*.zip" |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if (-not $collection) {
        throw "No OSAKA collection found. Run collect-osaka.ps1 first."
    }
    $CollectionPath = $collection.FullName
}

if (-not (Test-Path $CollectionPath)) {
    throw "Collection file was not found: $CollectionPath"
}
if (-not (Get-Command curl.exe -ErrorAction SilentlyContinue)) {
    throw "curl.exe is required to upload the OSAKA collection."
}

& curl.exe --fail --silent --show-error -F "file=@$CollectionPath" $LoaderUrl
if ($LASTEXITCODE -ne 0) {
    throw "OSAKA collection upload failed."
}

Write-Host "OSAKA collection uploaded: $CollectionPath"
