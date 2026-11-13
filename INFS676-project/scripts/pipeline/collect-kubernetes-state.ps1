$ErrorActionPreference = "Stop"

$projectRoot = Split-Path (Split-Path -Parent $PSScriptRoot) -Parent
$outputDir = Join-Path $projectRoot "data\raw"
$outputPath = Join-Path $outputDir "kubernetes-state.json"
$context = "cloud-twin"
$namespace = "cloud-twin"

function Get-KubernetesJson {
    param([string[]]$Arguments)
    $result = & kubectl --context $context @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Kubernetes collection command failed: kubectl $($Arguments -join ' ')"
    }
    if (-not $result) {
        return @{ items = @() }
    }
    return ($result -join "`n") | ConvertFrom-Json
}

kubectl config get-contexts $context | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "Kubernetes context '$context' was not found."
}

New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
$serviceAccounts = Get-KubernetesJson @("-n", $namespace, "get", "serviceaccounts", "-o", "json")
$deployments = Get-KubernetesJson @("-n", $namespace, "get", "deployments", "-o", "json")
$roles = Get-KubernetesJson @("-n", $namespace, "get", "roles", "-o", "json")
$clusterRoles = Get-KubernetesJson @("get", "clusterroles", "-o", "json")
$roleBindings = Get-KubernetesJson @("-n", $namespace, "get", "rolebindings", "-o", "json")
$clusterRoleBindings = Get-KubernetesJson @("get", "clusterrolebindings", "-o", "json")
$secrets = Get-KubernetesJson @("-n", $namespace, "get", "secrets", "-o", "json")

$state = [ordered]@{
    collectedAt = (Get-Date).ToUniversalTime().ToString("o")
    context = $context
    kubernetes = [ordered]@{
        serviceAccounts = @($serviceAccounts.items | ForEach-Object {
            [ordered]@{
                name = $_.metadata.name
                namespace = $_.metadata.namespace
                annotations = $_.metadata.annotations
            }
        })
        workloads = @($deployments.items | ForEach-Object {
            [ordered]@{
                name = $_.metadata.name
                namespace = $_.metadata.namespace
                serviceAccount = if ($_.spec.template.spec.serviceAccountName) { $_.spec.template.spec.serviceAccountName } else { "default" }
                tier = $_.spec.template.metadata.labels.tier
            }
        })
        roles = @(
            @($roles.items | ForEach-Object {
                [ordered]@{
                    kind = "Role"
                    name = $_.metadata.name
                    namespace = $_.metadata.namespace
                    rules = @($_.rules)
                }
            })
            @($clusterRoles.items | ForEach-Object {
                [ordered]@{
                    kind = "ClusterRole"
                    name = $_.metadata.name
                    rules = @($_.rules)
                }
            })
        )
        roleBindings = @(
            @($roleBindings.items | ForEach-Object {
                [ordered]@{
                    name = $_.metadata.name
                    namespace = $_.metadata.namespace
                    roleRef = [ordered]@{ kind = $_.roleRef.kind; name = $_.roleRef.name }
                    subjects = @($_.subjects)
                }
            })
            @($clusterRoleBindings.items | ForEach-Object {
                [ordered]@{
                    name = $_.metadata.name
                    namespace = ""
                    roleRef = [ordered]@{ kind = $_.roleRef.kind; name = $_.roleRef.name }
                    subjects = @($_.subjects)
                }
            })
        )
        secrets = @($secrets.items | ForEach-Object {
            [ordered]@{
                name = $_.metadata.name
                namespace = $_.metadata.namespace
                type = $_.type
            }
        })
    }
}

$state | ConvertTo-Json -Depth 30 | Set-Content -Path $outputPath -Encoding UTF8
Write-Host "Collected Kubernetes state without secret values: $outputPath"
