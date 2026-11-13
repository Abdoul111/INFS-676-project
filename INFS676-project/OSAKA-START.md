# OSAKA quick start

OSAKA is an optional Kubernetes configuration viewer for this project. It is
installed locally under `.tools\osaka` and is not committed to the repository.

## Prerequisites

- Docker Desktop running
- Git
- Python
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

## Upload current Kubernetes state

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
