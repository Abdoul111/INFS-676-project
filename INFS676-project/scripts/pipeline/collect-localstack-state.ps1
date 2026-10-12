$ErrorActionPreference = "Stop"

$projectRoot = Split-Path (Split-Path -Parent $PSScriptRoot) -Parent
$outputDir = Join-Path $projectRoot "data\raw"
$outputPath = Join-Path $outputDir "localstack-state.json"
$container = "cloud-twin-localstack"

function Invoke-LocalStackJson {
    param([string[]]$Arguments)
    $output = & docker exec $container awslocal @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "LocalStack collection command failed: awslocal $($Arguments -join ' ')"
    }
    return ($output -join "`n") | ConvertFrom-Json
}

docker inspect $container | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "Container '$container' is not running. Start the environment first."
}

$health = Invoke-RestMethod -Uri "http://localhost:4566/_localstack/health" -Method Get -TimeoutSec 10
if ($health.services.iam -notin @("available", "running") -or $health.services.s3 -notin @("available", "running")) {
    throw "LocalStack IAM and S3 must both be available before collection."
}

New-Item -ItemType Directory -Path $outputDir -Force | Out-Null

$state = [ordered]@{
    collectedAt = (Get-Date).ToUniversalTime().ToString("o")
    region = "us-east-1"
    endpoint = "http://localhost:4566"
    identityMappings = @(
        [ordered]@{
            workload = "web-pod"
            namespace = "cloud-twin"
            serviceAccount = "web-sa"
            roleArn = "arn:aws:iam::000000000000:role/cloud-twin-web-role"
        },
        [ordered]@{
            workload = "api-pod"
            namespace = "cloud-twin"
            serviceAccount = "api-sa"
            roleArn = "arn:aws:iam::000000000000:role/cloud-twin-api-role"
        }
    )
    roles = @()
    buckets = @()
}

$roleList = Invoke-LocalStackJson @("iam", "list-roles")
foreach ($roleSummary in @($roleList.Roles)) {
    $roleName = $roleSummary.RoleName
    $role = Invoke-LocalStackJson @("iam", "get-role", "--role-name", $roleName)
    $policies = Invoke-LocalStackJson @("iam", "list-role-policies", "--role-name", $roleName)
    $policyDocuments = @()
    foreach ($policyName in @($policies.PolicyNames)) {
        $policy = Invoke-LocalStackJson @("iam", "get-role-policy", "--role-name", $roleName, "--policy-name", $policyName)
        $policyDocuments += [ordered]@{
            name = $policyName
            document = $policy.PolicyDocument
        }
    }
    $state.roles += [ordered]@{
        roleName = $role.Role.RoleName
        roleArn = $role.Role.Arn
        trustPolicy = $role.Role.AssumeRolePolicyDocument
        inlinePolicies = $policyDocuments
    }
}

$bucketList = Invoke-LocalStackJson @("s3api", "list-buckets")
foreach ($bucket in @($bucketList.Buckets)) {
    $objects = Invoke-LocalStackJson @("s3api", "list-objects-v2", "--bucket", $bucket.Name)
    $state.buckets += [ordered]@{
        name = $bucket.Name
        creationDate = $bucket.CreationDate
        objects = @($objects.Contents | ForEach-Object {
            [ordered]@{
                key = $_.Key
                size = $_.Size
                etag = $_.ETag
            }
        })
    }
}

$state | ConvertTo-Json -Depth 20 | Set-Content -Path $outputPath -Encoding UTF8
Write-Host "Collected LocalStack state: $outputPath"
