# OSAKA quick start

OSAKA is the primary project visualization layer. It combines the Kubernetes
collection with the Cloud Twin IAM/S3 attack graph in Neo4j. It is installed
locally under `.tools\osaka` and is not committed to the repository.

## Prerequisites

- Docker Desktop running
- Git
- Python
- Minikube
- `kubectl` configured with the `cloud-twin` context for collection

## Start OSAKA

From the project directory:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\osaka\start-osaka.ps1
```

The script downloads the pinned OSAKA revision, creates local configuration,
builds the loader, and starts the Docker services.

Open the read-only dashboard at:

```text
http://127.0.0.1:8082
```

If NeoDash asks for a connection, use:

- URI: `bolt://127.0.0.1:7687`
- Username: `neo4j`
- Password: `OsakaLocalOnly-ChangeMe`
- Database: `neo4j`

The editor is available at `http://127.0.0.1:8081`. The loader is available at
`http://127.0.0.1:8080`.

For Neo4j/NeoDash connections, use:

- URI: `bolt://127.0.0.1:7687`
- Username: `neo4j`
- Password: `OsakaLocalOnly-ChangeMe`
- Database: `neo4j`

Edits made in the OSAKA editor are saved in Neo4j, not back to the project JSON.
Running the sync publisher restores the JSON version of `Cloud Twin Security
Dashboard`, so make permanent changes in
`integrations\osaka\project-dashboard.json`.

## Customize and reload the project dashboard

The project dashboard is defined in
`integrations\osaka\project-dashboard.json`. To publish changes without
recreating LocalStack or Kubernetes:

```powershell
python .\scripts\osaka\publish-project-dashboard.py `
    .\integrations\osaka\project-dashboard.json `
    --password OsakaLocalOnly-ChangeMe
```

Then reload `http://127.0.0.1:8082` with `Ctrl+F5`. The regular sync command
also republishes this JSON, but does not need `-RefreshEnvironment` for
dashboard-only changes.

Graph colors are controlled by each graph report's `styleRules`. NeoDash
applies those rules to graph nodes; table reports do not inherit graph node
colors. The attack-path table therefore exposes `SourceType` and `TargetType`
columns, while the findings table exposes severity and remediation.

## Run the unified synchronization

This is the recommended workflow for normal use. It starts OSAKA, reads the
existing graph JSON and catalog, and publishes the project dashboard without
recreating LocalStack or Kubernetes:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\osaka\sync-osaka.ps1
```

Open `http://127.0.0.1:8082` after the command completes. The dashboard
contains the unified graph, predicted attack paths, catalog findings, and
OSAKA Kubernetes analysis.

The visualizer is configured to open `Cloud Twin Security Dashboard`, not
OSAKA's stock `Dashboard`. If the page was already open, use `Ctrl+F5` after
synchronization to reload the dashboard configuration.

To explicitly refresh the simulated environment and recollect live state:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\osaka\sync-osaka.ps1 `
    -RefreshEnvironment
```

To upload a previously saved OSAKA collection without rebuilding the
environment:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\osaka\sync-osaka.ps1 `
    -ExistingCollectionPath .\data\osaka\collect-cloud-twin-latest.zip
```

## Upload current Kubernetes state only

With the `cloud-twin` cluster running:

```powershell
$collection = powershell -ExecutionPolicy Bypass -File .\scripts\osaka\collect-osaka.ps1 |
    Select-Object -Last 1
powershell -ExecutionPolicy Bypass -File .\scripts\osaka\upload-osaka-collection.ps1 `
    -CollectionPath $collection
```

Secret values are removed before the collection ZIP is created.

## Stop OSAKA

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\osaka\stop-osaka.ps1
```

The generated `.tools\osaka` checkout and `data\osaka` collections are ignored
by Git and can be retained between runs.
