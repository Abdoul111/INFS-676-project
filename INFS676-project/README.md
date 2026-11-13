# Cloud Security Digital Twin: Predicting Attack Paths in a Simulated Cloud Environment

## Project overview

This project investigates how a cloud environment can be modeled as a graph so that a compromised component can be evaluated for its blast radius before an attacker reaches a sensitive target. Instead of treating security issues as isolated findings, the system reasons about how multiple misconfigurations connect into attack chains.

The objective is to build a small, testable prototype that simulates a cloud system, collects security-relevant state, normalizes it into a graph, and predicts whether a compromise can lead to a critical path.

Prepared by:
- Abd Alwahed Haj Omar
- Avner Sehayek
- Dallas Thompson

---

## Research focus

The core research question is:

How can a simulated cloud environment be represented as a graph of identities, permissions, workloads, and network paths so that attack paths can be predicted from a compromised resource?

The project focuses on cloud security posture and uses a graph-based model to reason about lateral movement and privilege escalation. The design is intentionally lightweight and realistic for a semester project rather than a full production system.

---

## Main objective

Build a cloud security digital twin that:

1. Simulates a cloud-like environment.
2. Captures IAM, bucket, workload, and network metadata.
3. Converts that data into a graph representation.
4. Models permissions and trust relationships.
5. Identifies attack paths from an initially compromised node.
6. Compares predicted paths with actual attack execution results.

---

## System architecture

The pipeline runs in multiple phases:

### Phase 1: Simulated environment
- **Completed:** Minikube cluster running with the Docker driver
- **Completed:** Public-facing `web-pod` and private `api-pod` deployed in the `cloud-twin` namespace
- **Completed:** Separate Kubernetes ServiceAccounts created for the two workloads
- **Completed:** LocalStack Community Edition running with IAM, S3, STS, and logs enabled
- **Completed:** Workloads configured to reach the Docker-hosted LocalStack instance at `host.docker.internal:4566`
- **Completed:** Explicit prototype mapping from `web-sa` and `api-sa` to separate LocalStack IAM roles
- **Completed:** Scenario-specific IAM policies, S3 buckets, and test objects provisioned in the shared LocalStack instance
- **Note:** The web and API workloads currently use `nginx:1.27-alpine` as placeholders. They provide the workload boundaries for the prototype but do not contain custom frontend or backend code.

### Phase 2: Data collection
- **Completed:** LocalStack IAM and S3 fixture state is available for collection
- **Completed:** Collect AWS-style IAM and S3 state from LocalStack
- **Completed:** Capture permissions, identities, policies, bucket metadata, and object metadata
- **Completed:** Log the collected configuration to `data/raw/localstack-state.json`

### Phase 3: Graph modeling and normalization
- **Completed:** Convert collected data into graph nodes and edges
- **Completed:** Model workloads, service accounts, roles, permissions, buckets, objects, and trust links
- **Completed:** Collect Kubernetes ServiceAccounts, workloads, Roles/ClusterRoles, RoleBindings/ClusterRoleBindings, and Secret metadata
- **Completed:** Model Kubernetes RBAC inheritance and Secret read reachability alongside IAM/S3 paths
- **Completed:** Build an initial graph from the collected state at `data/graph/attack-graph.json`
- **Completed:** Encode allow/deny policy evaluation for action/resource matches
- **Completed:** Apply explicit-deny precedence and wildcard action/resource matching
- **Pending:** Evaluate policy conditions instead of conservatively excluding conditional statements

### Phase 4: Attack-path engine and validation
- **Completed:** Search the graph from a compromised `web-pod`
- **Completed:** Identify direct public-object, API-role, and sensitive-object paths
- **Completed:** Generate reachability data for every graph entity, not only `web-pod`
- **Completed:** Serve the generated graph through the Flask/Cytoscape.js visualization
- **Completed:** Verify the visualization page and `/api/graph` endpoint return the current 21-node, 26-edge graph with entity-specific reachability
- **Pending:** Execute controlled actions and compare them with graph predictions
- **Pending:** Compare predicted paths against executed attacks
- **Pending:** Record pass/fail outcomes and whether the path is valid

### Kubernetes attack modeling

The pipeline now collects Kubernetes metadata with
[`collect-kubernetes-state.ps1`](./scripts/pipeline/collect-kubernetes-state.ps1). Secret values are
never collected. The collector writes `data/raw/kubernetes-state.json`; the graph builder merges
that snapshot with the LocalStack snapshot and represents RBAC bindings, permissions, and Secret
read transitions.

Run the combined pipeline after starting the environment:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\pipeline\run-data-pipeline.ps1
```

The generated graph includes `blastRadius` entries for every source. Each entry reports reachable
node count, reachable sensitive-node count, sensitive targets, and path count. Sensitive targets
currently include S3 objects and Kubernetes Secrets.

The project also includes reproducible offline scenarios:

```powershell
python .\scripts\pipeline\generate-kubernetes-scenarios.py
python .\scripts\pipeline\validate-kubernetes-scenarios.py .\data\raw\localstack-state.json
```

The validator compares vulnerable, restricted, and mixed RBAC configurations. It is intentionally
separate from live attack execution so graph behavior can be tested without exposing real Secret
values or requiring a cloud provider.

The collector and graph pipeline are now working. The visualization can select any graph entity and highlight its reachable entities. The remaining core work is condition-aware policy evaluation and empirical validation against controlled attack actions. Trust relationships are collected and represented in the graph; role-assumption reachability is currently derived from matching permission and resource statements and is not yet validated against an observed credential exchange.

### OSAKA integration

OSAKA (ANSSI-FR's *Outil de Sécurité des Architectures Kubernetes Avancées*) is
available as an optional Kubernetes-focused graph viewer. It runs in its own
Docker Compose stack and does not change the LocalStack or project graph
pipeline.

See [`OSAKA-START.md`](./OSAKA-START.md) for the short installation, dashboard,
collection, and shutdown instructions.

Install and start it from PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\osaka\start-osaka.ps1
```

The script pins the upstream OSAKA checkout, configures a local Neo4j password,
uses the published NeoDash `2.4.8` image for the visualizer, and starts the loader on
`http://127.0.0.1:8080`, the editor on `http://127.0.0.1:8081`, and the
read-only visualizer on `http://127.0.0.1:8082`. Set `OSAKA_HOST_IP` and
`OSAKA_NEO4J_PASSWORD` to override the local defaults.

After the `cloud-twin` Minikube profile is running, collect and upload
Kubernetes metadata:

```powershell
$collection = powershell -ExecutionPolicy Bypass -File .\scripts\osaka\collect-osaka.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\osaka\upload-osaka-collection.ps1 -CollectionPath $collection[-1]
```

The collection removes Secret data before creating the ZIP. Stop OSAKA with
`.\scripts\osaka\stop-osaka.ps1`. OSAKA is intended for an isolated local
environment; do not expose its editor or loader publicly.

### Script organization

The scripts are grouped by the part of the system they operate:

- `scripts/environment/` — start, stop, and validate Docker/Minikube
- `scripts/localstack/` — provision IAM roles, policies, buckets, and test objects
- `scripts/pipeline/` — collect LocalStack state, build the attack graph, and validate predicted paths
- `scripts/web/` — start the Flask graph visualization

### Graph visualization

The attack graph is now available through a small Flask and Cytoscape.js web application. The visualization can reload the current graph or regenerate the graph from the current LocalStack state.

Install the web dependency once:

```powershell
pip install -r .\web\requirements.txt
```

Start the visualization:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\web\run-visualization.ps1
```

Open `http://127.0.0.1:5000` in a browser. The page displays the graph, predicted paths, and details for selected nodes or edges. Each permission square represents one action/resource grant, such as `s3:GetObject` on a bucket or object. Graph zoom is controlled with the `+` and `−` buttons so the mouse wheel remains available for normal page scrolling. It is a visualization of the JSON-backed graph, not a replacement for the collector or graph-building pipeline.

Use **Reload graph** after an external pipeline run. The browser does not poll the API continuously or append timestamp query parameters; it makes one graph request when the page opens and another only when a user clicks **Reload graph** or completes **Regenerate from LocalStack**. If an older visualization tab remains open, close it before opening the current page because that already-loaded tab can continue executing an earlier script. Regeneration starts the project LocalStack container if needed, provisions the project fixtures, collects the IAM/S3 state, and rebuilds the graph directly from the browser. Docker Desktop must be available. Use **Explore from an identity** to choose a workload, service account, or IAM role as the starting point; permissions are integrated into role-to-resource links, while buckets and objects remain graph destinations rather than selectable sources. Hover over a connected entity to see its permissions, and click it to show each permission on a separate line in the details panel. Transitions do not display hover tooltips. Select **Show reachable** to highlight that identity's directed reachability and list its paths. Unrelated entities stay visible at a readable opacity. The risk legend distinguishes normal user-facing access, backend resources, identity/elevation boundaries, and takeover/backdoor paths. The graph is organized into workload, identity/trust, and storage layers, with different shapes for each component type.

The main commands are:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\environment\start-environment.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\environment\validate-environment.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\pipeline\validate-attack-graph.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\environment\stop-environment.ps1
```

The environment startup script calls the LocalStack provisioning and data-pipeline scripts automatically.

---

## Abd Alwahed execution plan

The following tasks are the primary execution workstream for Abd Alwahed. They are written as actionable steps with expected outcome and completion checkpoints.

### Task 1: Set up the simulated environment

Objective:
Set up the local environment that will act as the cloud digital twin sandbox.

Execution steps:
1. Prepare a local Kubernetes cluster using a lightweight option such as kind or minikube.
2. Deploy the simulated workloads needed for the attack chain.
3. Configure a public web pod and a backend API pod.
4. Bind each pod to a unique service account and map it to a LocalStack IAM role.
5. Ensure the environment can be reset quickly for repeated testing.

Expected outcome:
A clean, repeatable sandbox exists where attack scenarios can be run and reset without manual cleanup.

Definition of done:
- [x] Cluster is running
- [x] Both workloads are deployed
- [x] Separate Kubernetes service accounts are attached to the workloads
- [x] LocalStack is available inside the cluster
- [x] Startup, validation, and shutdown scripts are available
- [x] Workload identities are explicitly mapped to LocalStack roles
- [x] The environment contains the IAM and S3 resources required for the attack scenario
- [x] The environment can be recreated using the project manifests and scripts

---

### Task 2: Define the graph schema and data model

Objective:
Implement the representation that captures identities, permissions, workloads, and relationships.

Execution steps:
1. Define nodes for identities, roles, workloads, storage resources, and trust paths.
2. Define edges for relationships such as attached policies, permissions, network access, and resource ownership.
3. Decide how privilege and reachability will be represented in the graph.
4. Prepare the normalizer to transform raw LocalStack/IAM data into graph-compatible objects.
5. Include policy evaluation logic that determines whether a principal can access a resource.

Expected outcome:
A graph schema exists that can represent a realistic attack surface and allow path discovery from a compromised node.

Definition of done:
- [x] Initial node and edge types are defined
- [x] IAM policy logic supports explicit deny and wildcard matching
- [ ] IAM policy logic evaluates conditions
- [x] Raw LocalStack configuration can be collected and normalized into graph form
- [x] Schema supports initial attack path queries
- [ ] Schema is validated against controlled attack results

Notes:
This is the hardest single technical piece in the project, and it should be treated as the core modeling task.

---

### Task 3: Build the graph storage and attack-path engine

Objective:
Create the logic that stores the graph and searches it for meaningful attack paths.

Execution steps:
1. Store graph data in the chosen structure, preferably NetworkX for the prototype.
2. Implement graph queries that start from a compromised resource.
3. Search for paths to high-value targets or sensitive resources.
4. Incorporate access evaluation so that only reachable and permitted transitions are considered valid.
5. Rank or classify paths by risk or likelihood.

Expected outcome:
The system can answer: if a resource is compromised, what valid attack chains can follow from it?

Definition of done:
- [x] Graph is stored and queryable
- [x] Initial attack-path search is functional
- [x] Initial paths are derived from permissions and trust relationships
- [x] Results are interpretable
- [ ] Results are verified against controlled attack execution

---

### Task 4: Connect the full pipeline end to end

Objective:
Unify the environment, data collection, graph model, and prediction logic into a single workflow.

Execution steps:
1. Connect the simulated environment to the collector.
2. Feed collected config and policy data into the normalizer.
3. Build the graph from normalized data.
4. Run the attack-path engine from a chosen compromised node.
5. Validate whether the predicted path matches real execution results.
6. Fix mismatches between expected and observed behavior.

Expected outcome:
The project pipeline runs end-to-end and can generate a real attack-path prediction from system state.

Definition of done:
- [x] Data flow is complete from environment to graph to result
- [x] Pipeline is reproducible
- [ ] Attack predictions can be validated against observed actions
- [x] The system works as a prototype digital twin

---

### Task 5: Support the team and unblock testing

Objective:
Keep the project moving by ensuring the pipeline is usable by other team members.

Execution steps:
1. Define the data collection template used by the rest of the team.
2. Provide a stable schema contract for shared inputs.
3. Document setup instructions for local execution.
4. Help validate that data collection and attack scripts work correctly.
5. Resolve integration issues that block Avner's collector work or the validation phase.

Expected outcome:
The team can work in parallel without breaking the data flow or test plan.

Definition of done:
- Shared template exists
- Setup instructions are clear
- Integration blockers are removed
- Pipeline can be used by multiple contributors

---

## Team responsibilities summary

### Abd Alwahed
Primary responsibilities:
- Set up the simulated environment
- Build the graph schema and normalizer
- Implement IAM policy-evaluation logic
- Build graph storage and the attack-path engine
- Connect all phases into one working pipeline

### Avner Sehayek
Primary responsibilities:
- Build the LocalStack data collector using boto3
- Capture IAM and S3 state
- Run attack scripts from a checklist
- Record pass/fail outcomes for validation

### Dallas Thompson
Primary responsibilities:
- Literature review and research background
- Support project framing and methodology
- Contribute to documentation and validation narrative

---

## Execution checklist for Abd Alwahed

Use this checklist as the working execution plan:

- [x] Build the local Kubernetes/Lambda-like simulation environment
- [x] Provision the Kubernetes workloads and service accounts
- [x] Map workload identities to LocalStack IAM roles
- [x] Configure LocalStack IAM and S3 simulation
- [x] Collect LocalStack IAM and S3 state
- [x] Define the initial graph schema
- [x] Implement the initial normalizer
- [x] Generate the initial attack graph
- [ ] Implement condition-aware IAM policy evaluation
- [ ] Validate IAM permission evaluation against controlled actions
- [x] Load graph nodes and edges
- [x] Implement starting-node attack search
- [x] Generate the attack-path prediction
- [ ] Validate results against executed attack steps
- [x] Document setup and current implementation status
- [ ] Document final findings and observed attack results

---

## Recommended project constraints

The project should remain focused and realistic. The team notes that the following are optional rather than mandatory:

- Secrets Manager
- More advanced policy handling
- Expanded scenarios
- Neo4j integration
- Additional attack variants

These items are useful only if time permits after the core pipeline is complete and validated.

---

## Expected deliverables

The final project should produce:

1. A working simulated cloud environment
2. A graph representation of cloud identities and resources
3. An IAM policy logic layer
4. An attack-path engine
5. A validation workflow comparing predicted vs. actual attack results
6. Results and discussion summarized in project documentation

---

## Final note

This project is not a machine-learning research project in the narrow sense. It is a graph-modeling and empirical-validation project whose main purpose is to show that a cloud security digital twin can predict likely attack paths from a compromised component using realistic cloud configuration data.

For Abd Alwahed, the priority is to build the runnable core: environment, schema, normalizer, graph logic, and end-to-end attack-path engine.
