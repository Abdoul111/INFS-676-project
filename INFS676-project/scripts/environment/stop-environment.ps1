$ErrorActionPreference = "Stop"

Write-Host "Stopping LocalStack container..."
docker rm -f cloud-twin-localstack 2>$null | Out-Null

Write-Host "Stopping Minikube profile..."
minikube stop -p cloud-twin 2>$null | Out-Null

Write-Host "Environment stopped."
