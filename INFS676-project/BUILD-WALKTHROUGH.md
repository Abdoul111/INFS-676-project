# Simulated Environment Build Walkthrough

This walkthrough records how the Cloud Security Digital Twin simulated environment was built. It explains what was set up, which problems occurred, and how they were fixed.

## Final Environment

The environment uses:

- Docker Desktop
- Minikube with the Docker driver
- LocalStack Community Edition
- Kubernetes namespace: `cloud-twin`
- Minikube profile: `cloud-twin`

The following Kubernetes workloads are running:

- `web-pod` — public-facing simulated workload
- `api-pod` — private backend simulated workload

LocalStack runs as a Docker service shared with the Minikube workloads. It provides:

- IAM
- S3
- STS
- CloudWatch Logs

## Project Files

```text
docker/
  docker-compose.localstack.yml
  localstack-data/

k8s/
  namespace.yaml
  identity-mapping.yaml
  workloads.yaml

fixtures/
  iam/
    api-role-policy.json
    api-role-trust-policy.json
    public-object.txt
    sensitive-object.txt
    web-role-policy.json
    web-role-trust-policy.json

data/
  raw/
    localstack-state.json
  graph/
    attack-graph.json

scripts/
  environment/
    start-environment.ps1
    stop-environment.ps1
    validate-environment.ps1
  localstack/
    provision-localstack.ps1
  pipeline/
    collect-localstack-state.ps1
    build-attack-graph.py
    run-data-pipeline.ps1
    validate-attack-graph.ps1
  web/
    run-visualization.ps1

web/
  app.py
  requirements.txt
  templates/index.html
  static/app.js
  static/styles.css
```

## Build Steps

### 1. Verify Installed Tools

Docker and Minikube were checked first:

```powershell
docker --version
minikube version
```

Docker and Minikube were available. LocalStack Desktop was also installed, but a command-line `localstack` executable was not found in `PATH`. LocalStack was therefore run directly from Docker.

### 2. Create the Project Structure

The following directories were created:

- `docker/` for LocalStack configuration and persisted data
- `k8s/` for Kubernetes manifests
- `scripts/environment/` for starting, stopping, and checking the running environment
- `scripts/localstack/` for provisioning LocalStack IAM and S3 fixtures
- `scripts/pipeline/` for collecting state, building the graph, and validating predicted paths
- `scripts/web/` for starting the graph visualization
- `web/` for the Flask application and browser assets

### 3. Configure LocalStack

LocalStack was configured in `docker/docker-compose.localstack.yml`.

Port `4566` was exposed and IAM, S3, STS, and logs were enabled. LocalStack state was configured to persist in `docker/localstack-data/`. The Kubernetes workloads reach this shared instance through `host.docker.internal:4566`.

Start LocalStack with:

```powershell
docker compose -f .\docker\docker-compose.localstack.yml up -d
```

Health was verified with:

```powershell
Invoke-RestMethod http://localhost:4566/_localstack/health
```

### 4. Create the Minikube Cluster

A dedicated Minikube profile called `cloud-twin` was created with the Docker driver:

```powershell
minikube start -p cloud-twin --driver=docker --memory=4096 --cpus=4 --disk-size=20g
```

The cluster was checked with:

```powershell
minikube status -p cloud-twin
kubectl --context cloud-twin get nodes
```

### 5. Apply Kubernetes Resources

The Kubernetes manifests create the `cloud-twin` namespace, service accounts, services, and deployments:

```powershell
kubectl --context cloud-twin apply -f .\k8s\namespace.yaml
kubectl --context cloud-twin -n cloud-twin apply -f .\k8s\workloads.yaml
```

The workloads were verified with:

```powershell
kubectl --context cloud-twin -n cloud-twin get deployments,pods,svc
```

After the images finished downloading, both Kubernetes deployments reached `1/1` Ready:

- `web-pod`
- `api-pod`

## Problems Encountered and Fixes

### Problem 1: PowerShell Blocked the Startup Script

The first attempt to run `start-environment.ps1` was blocked because the machine execution policy does not allow scripts to run.

Error:

```text
running scripts is disabled on this system
```

For this run, the script was launched with a temporary execution-policy bypass:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\environment\start-environment.ps1
```

The bypass applied only to that PowerShell process. The machine-wide execution policy was not changed.

### Problem 2: The `latest` LocalStack Image Required an Auth Token

The initial Compose file used `localstack/localstack:latest`. When it was started, the container exited because that release required a LocalStack authentication token.

Error:

```text
License activation failed!
No credentials were found in the environment.
```

The issue was fixed by:

- Replacing `localstack/localstack:latest` with the pinned community-compatible image `localstack/localstack:3.8.1`
- Removing the failed container
- Starting the pinned image again

The pinned image started successfully and reported:

```text
edition: community
version: 3.8.1
```

Pinning the image also makes future setup more reproducible than using `latest`.

### Problem 3: The Minikube kubectl Wrapper Used a Stale API Endpoint

Minikube reported that the cluster was running, but this command:

```powershell
minikube kubectl -- get nodes
```

attempted to connect to an unavailable `127.0.0.1` API endpoint.

After testing the connection, the issue was fixed by:

- Confirming that the standalone Docker Desktop `kubectl.exe` was available
- Using the working context directly:

```powershell
kubectl --context cloud-twin get nodes
```

- Updating the project scripts to use `kubectl --context cloud-twin` when applying manifests and checking rollout status

### Problem 4: Kubernetes Rejected the `hostAliases` Configuration

The first workload manifest used this value as an IP address:

```yaml
hostAliases:
  - ip: "host.minikube.internal"
```

Kubernetes rejected it because `hostAliases.ip` must contain a literal IP address, not a hostname.

The manifest was corrected by:

- Removing the invalid `hostAliases` entries
- Configuring the workloads to use the shared Docker-hosted endpoint:

```text
http://host.docker.internal:4566
```

After testing the revised configuration, the workloads reached the same Docker-hosted LocalStack instance that was used to provision the IAM and S3 fixtures.

### Problem 5: Two LocalStack Instances Were Running

The first Kubernetes manifest revision started one LocalStack container in Docker and another LocalStack deployment inside Minikube. The IAM and S3 fixtures were provisioned into the Docker container, while the workloads were configured to use the in-cluster service. This meant the workloads and the provisioned fixture state were using different LocalStack instances.

After checking the endpoint from inside `web-pod`, the setup was simplified:

- The duplicate in-cluster LocalStack deployment and service were removed.
- The Docker-hosted LocalStack container became the single shared instance.
- The workloads were configured to use `http://host.docker.internal:4566`.
- The endpoint was tested successfully from inside the Kubernetes workload.

This ensures that the roles, policies, buckets, and objects being analyzed are the same resources reachable by the simulated workloads.

## Data and Graph Pipeline

After the IAM and S3 fixtures were provisioned, the next phase was implemented:

1. `scripts/pipeline/collect-localstack-state.ps1` queries the shared LocalStack instance.
2. IAM roles, trust policies, inline policies, S3 buckets, objects, and workload mappings are written to `data/raw/localstack-state.json`.
3. `scripts/pipeline/build-attack-graph.py` converts the collected state into nodes and relationships in `data/graph/attack-graph.json`.
4. The graph starts from a compromised `web-pod` and follows all modeled reachable relationships, not only the API-role path.
5. `scripts/pipeline/validate-attack-graph.ps1` checks for the public-object path, the API role-assumption path, and the sensitive-object path.

The current modeled blast radius includes:

- Direct access to the public bucket and its object
- Discovery of the web IAM role and its permissions
- Assumption of the API IAM role
- Access to the sensitive bucket and sensitive object through the API role

The graph is a prediction model. LocalStack Community Edition does not automatically enforce the Kubernetes ServiceAccount annotations as real cloud credentials, so the Kubernetes-to-IAM relationship is represented explicitly in the collected state and graph. Permission records remain in the underlying graph data for reachability and validation, but the visualizer integrates them into direct role-to-resource links instead of displaying a separate permission layer. Hovering a connected entity shows its permissions without adding hover behavior to transitions, and clicking an entity lists each related permission separately in the details panel.

## Web Visualization

The graph is served by `web/app.py`. The Flask page calls `/api/graph`, loads the current graph, and renders it interactively with Cytoscape.js. Selecting a node or edge shows its collected properties, while the predicted-path list can highlight a modeled path.

The interface now provides three graph lifecycle controls:

- **Reload graph** reads the latest generated graph without running collection.
- **Regenerate from LocalStack** runs the existing collector and graph builder through `POST /api/regenerate`.
- The browser does not poll the graph API continuously. Use **Reload graph** after an external pipeline run, or use **Regenerate from LocalStack** to rebuild and display the latest state.

Graph zoom is controlled with the `+` and `−` buttons rather than the mouse wheel. This keeps page scrolling usable while the graph is open.

Permission nodes are intentionally granular: every action/resource combination from an inline IAM policy becomes a separate permission square. The edge now shows the action, for example `allows s3:GetObject`, instead of only the generic `has_permission` relation. Workload identity links are labeled `runs as` and `maps to IAM role` so the path from a pod to its modeled IAM role is explicit.

Long node names and permission targets are wrapped at a fixed character limit so ARNs and resource paths do not stretch across neighboring layers.

The path model now exposes reachability for every graph entity. The graph builder applies action/resource wildcard matching, denies matching permissions when an explicit `Deny` is present, and does not treat statements with conditions as reachable until condition evaluation is implemented. The visualizer lets the user choose any workload, service account, role, permission, bucket, object, or trust principal and highlight its directed reachable entities.

Reachability highlighting keeps unrelated entities visible instead of nearly hiding them. A risk legend classifies normal user-facing resources, backend resources, identity/elevation boundaries, and takeover/backdoor relationships. These are visual classifications for triage; a service account is treated as an identity boundary, not automatically as a compromise.

Regeneration starts the project Docker Compose LocalStack service when necessary, waits until IAM and S3 are healthy, reapplies the project fixtures, and then runs collection and graph construction. If Docker or LocalStack cannot become ready, the API returns the failure details instead of showing a successful-looking graph.

The application was started with:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\web\run-visualization.ps1
```

The page at `http://127.0.0.1:5000/` returned successfully, and `/api/graph` returned 21 nodes, 26 edges, and 3 predicted paths. The graph is still persisted as JSON, but it can now be refreshed or regenerated from the interface. The graph presentation uses four visual layers and distinct node shapes to reduce overlap and make workloads, identities, permissions, and storage easier to distinguish.

During setup, the package installer helper reported a failed Flask installation attempt. A direct import check showed that Flask `3.1.0` was already available in the selected Python environment, so no additional installation was needed. The browser initially reported Cytoscape label warnings for permission nodes without a `name` field. The node label style was changed to use an empty label when `name` is absent, and the page was reloaded successfully.

## Final Validation

The final validation confirmed that:

- Minikube profile `cloud-twin` is running.
- The Kubernetes node is Ready.
- The `cloud-twin` namespace exists.
- `web-pod` is Running and Ready.
- `api-pod` is Running and Ready.
- LocalStack is healthy.
- The Kubernetes services for web and API are available.

## Useful Commands

Start the environment again:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\environment\start-environment.ps1
```

Validate the environment:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\environment\validate-environment.ps1
```

Stop the environment:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\environment\stop-environment.ps1
```

View Kubernetes resources:

```powershell
kubectl --context cloud-twin -n cloud-twin get all
```

View LocalStack logs:

```powershell
docker logs cloud-twin-localstack
```

## Next Step

The collector and initial graph are now in place, and the graph can be viewed through the Flask/Cytoscape.js application:

```powershell
pip install -r .\web\requirements.txt
powershell -ExecutionPolicy Bypass -File .\scripts\web\run-visualization.ps1
```

Open `http://127.0.0.1:5000` to inspect the graph. The visualization reads `data/graph/attack-graph.json`; rerun the data pipeline to refresh the graph shown in the browser.

The next engineering step is to strengthen policy evaluation by handling explicit denies, wildcard matching, and role-assumption semantics, then compare the predicted graph paths with controlled LocalStack attack actions.
