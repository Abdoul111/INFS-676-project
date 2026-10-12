$ErrorActionPreference = "Stop"

$projectRoot = Split-Path (Split-Path -Parent $PSScriptRoot) -Parent
$localstackCompose = Join-Path $projectRoot "docker\docker-compose.localstack.yml"
$k8sDir = Join-Path $projectRoot "k8s"
$provisionScript = Join-Path $projectRoot "scripts\localstack\provision-localstack.ps1"
$pipelineScript = Join-Path $projectRoot "scripts\pipeline\run-data-pipeline.ps1"

Write-Host "Checking Docker status..."
docker info | Out-Null

Write-Host "Starting LocalStack container..."
docker compose -f $localstackCompose up -d

for ($attempt = 1; $attempt -le 30; $attempt++) {
    try {
        $health = Invoke-RestMethod -Uri "http://localhost:4566/_localstack/health" -Method Get -TimeoutSec 10
        if ($health -and $health.services) {
            Write-Host "LocalStack health check passed."
            break
        }
    }
    catch {
        if ($attempt -eq 30) {
            throw "LocalStack did not become healthy in time."
        }
        Start-Sleep -Seconds 2
    }
}

$profile = "cloud-twin"
$minikubeStatus = minikube status -p $profile 2>$null
if (-not $minikubeStatus) {
    Write-Host "Starting Minikube cluster..."
    minikube start -p $profile --driver=docker --memory=4096 --cpus=4 --disk-size=20g
}
elseif ($minikubeStatus -notmatch "host: Running") {
    Write-Host "Starting existing Minikube profile..."
    minikube start -p $profile --driver=docker
}
else {
    Write-Host "Minikube is already running."
}

Write-Host "Applying Kubernetes manifests..."
kubectl --context cloud-twin apply -f (Join-Path $k8sDir "namespace.yaml")
kubectl --context cloud-twin apply -f (Join-Path $k8sDir "identity-mapping.yaml")
kubectl --context cloud-twin -n cloud-twin apply -f (Join-Path $k8sDir "workloads.yaml")

Write-Host "Waiting for workloads to become ready..."
kubectl --context cloud-twin -n cloud-twin rollout status deployment/web-pod --timeout=180s
kubectl --context cloud-twin -n cloud-twin rollout status deployment/api-pod --timeout=180s

Write-Host "Provisioning LocalStack IAM and S3 fixtures..."
powershell -ExecutionPolicy Bypass -File $provisionScript
if ($LASTEXITCODE -ne 0) {
    throw "LocalStack provisioning failed."
}

Write-Host "Collecting LocalStack state and building the attack graph..."
powershell -ExecutionPolicy Bypass -File $pipelineScript
if ($LASTEXITCODE -ne 0) {
    throw "Data pipeline failed."
}

Write-Host "Environment is ready."
Write-Host "LocalStack: http://localhost:4566"
Write-Host "Minikube profile: $profile"
Write-Host "Kubernetes namespace: cloud-twin"
