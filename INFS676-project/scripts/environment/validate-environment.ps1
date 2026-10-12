$ErrorActionPreference = "Stop"

Write-Host "Testing LocalStack health..."
$health = Invoke-RestMethod -Uri "http://localhost:4566/_localstack/health" -Method Get -TimeoutSec 10
$health | Format-List

Write-Host "Testing Kubernetes cluster..."
minikube status -p cloud-twin
kubectl --context cloud-twin -n cloud-twin get pods
kubectl --context cloud-twin -n cloud-twin get serviceaccounts web-sa api-sa -o yaml
kubectl --context cloud-twin -n cloud-twin get configmap cloud-identity-mapping -o yaml

Write-Host "Testing LocalStack IAM and S3 fixtures..."
docker exec cloud-twin-localstack awslocal iam get-role --role-name cloud-twin-web-role
docker exec cloud-twin-localstack awslocal iam get-role --role-name cloud-twin-api-role
docker exec cloud-twin-localstack awslocal s3 ls s3://cloud-twin-public
docker exec cloud-twin-localstack awslocal s3 ls s3://cloud-twin-sensitive

Write-Host "Validation complete."
