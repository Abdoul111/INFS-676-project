$ErrorActionPreference = "Stop"

$projectRoot = Split-Path (Split-Path -Parent $PSScriptRoot) -Parent
$fixtureDir = Join-Path $projectRoot "fixtures\iam"
$container = "cloud-twin-localstack"
$region = "us-east-1"

function Invoke-LocalStack {
    param([string[]]$Arguments)
    & docker exec $container awslocal @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "LocalStack command failed: awslocal $($Arguments -join ' ')"
    }
}

docker inspect $container | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "Container '$container' is not running. Start the environment first."
}

Write-Host "Checking LocalStack health..."
$health = Invoke-RestMethod -Uri "http://localhost:4566/_localstack/health" -Method Get -TimeoutSec 10
if ($health.services.iam -notin @("available", "running") -or $health.services.s3 -notin @("available", "running")) {
    throw "LocalStack IAM and S3 must both be available before provisioning."
}

Write-Host "Copying IAM policy fixtures into LocalStack..."
docker cp (Join-Path $fixtureDir "web-role-trust-policy.json") "${container}:/tmp/web-role-trust-policy.json"
docker cp (Join-Path $fixtureDir "api-role-trust-policy.json") "${container}:/tmp/api-role-trust-policy.json"
docker cp (Join-Path $fixtureDir "web-role-policy.json") "${container}:/tmp/web-role-policy.json"
docker cp (Join-Path $fixtureDir "api-role-policy.json") "${container}:/tmp/api-role-policy.json"
docker cp (Join-Path $fixtureDir "public-object.txt") "${container}:/tmp/public-object.txt"
docker cp (Join-Path $fixtureDir "sensitive-object.txt") "${container}:/tmp/sensitive-object.txt"

& $env:ComSpec /c "docker exec $container awslocal iam get-role --role-name cloud-twin-web-role >nul 2>nul"
if ($LASTEXITCODE -ne 0) {
    Invoke-LocalStack @("iam", "create-role", "--role-name", "cloud-twin-web-role", "--assume-role-policy-document", "file:///tmp/web-role-trust-policy.json")
}
& $env:ComSpec /c "docker exec $container awslocal iam get-role --role-name cloud-twin-api-role >nul 2>nul"
if ($LASTEXITCODE -ne 0) {
    Invoke-LocalStack @("iam", "create-role", "--role-name", "cloud-twin-api-role", "--assume-role-policy-document", "file:///tmp/api-role-trust-policy.json")
}

Invoke-LocalStack @("iam", "put-role-policy", "--role-name", "cloud-twin-web-role", "--policy-name", "cloud-twin-web-policy", "--policy-document", "file:///tmp/web-role-policy.json")
Invoke-LocalStack @("iam", "put-role-policy", "--role-name", "cloud-twin-api-role", "--policy-name", "cloud-twin-api-policy", "--policy-document", "file:///tmp/api-role-policy.json")

Write-Host "Creating S3 buckets and test objects..."
& $env:ComSpec /c "docker exec $container awslocal s3api head-bucket --bucket cloud-twin-public >nul 2>nul"
if ($LASTEXITCODE -ne 0) {
    Invoke-LocalStack @("s3", "mb", "s3://cloud-twin-public", "--region", $region)
}
& $env:ComSpec /c "docker exec $container awslocal s3api head-bucket --bucket cloud-twin-sensitive >nul 2>nul"
if ($LASTEXITCODE -ne 0) {
    Invoke-LocalStack @("s3", "mb", "s3://cloud-twin-sensitive", "--region", $region)
}
Invoke-LocalStack @("s3", "cp", "/tmp/public-object.txt", "s3://cloud-twin-public/public-object.txt")
Invoke-LocalStack @("s3", "cp", "/tmp/sensitive-object.txt", "s3://cloud-twin-sensitive/sensitive-object.txt")

Write-Host "LocalStack IAM and S3 fixtures are ready."
