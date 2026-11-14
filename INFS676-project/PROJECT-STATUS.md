# Cloud Security Digital Twin: Project Status

## Overall assessment

The runnable prototype is substantially built, but the project is not fully complete until controlled attack actions are executed and compared with the predicted graph paths.

The current generated artifact contains 21 graph nodes, 26 graph edges, and 7 unique predicted paths from `web-pod`. The three required scenario paths all pass validation. These figures describe the JSON snapshot and should be refreshed by rerunning the pipeline after the LocalStack fixtures change.

The current working pipeline is:

```text
Minikube + LocalStack environment
        ↓
IAM/S3 + Kubernetes state collection
        ↓
Normalized IAM/RBAC graph
        ↓
Permission and trust modeling
        ↓
Reachability prediction
        ↓
Blast-radius metrics
        ↓
Interactive visualization
```

The current graph demonstrates the intended escalation scenario:

```text
web-pod
→ web-sa
→ cloud-twin-web-role
→ sts:AssumeRole
→ cloud-twin-api-role
→ sensitive S3 bucket
→ sensitive object
```

## Abd Alwahed

### Completed responsibilities

The main Abd Alwahed engineering responsibilities are implemented:

| Responsibility | Status | Evidence |
|---|---:|---|
| Simulated Kubernetes environment | Done | Minikube, `web-pod`, `api-pod`, and service accounts |
| LocalStack IAM/S3 environment | Done | IAM roles, policies, buckets, and objects |
| Workload-to-role mapping | Done | `web-sa` → `cloud-twin-web-role`; `api-sa` → `cloud-twin-api-role` |
| Graph schema | Done | Workloads, service accounts, roles, principals, permissions, buckets, and objects |
| Data normalization | Done | LocalStack state converted into graph nodes and edges |
| Graph storage | Done | `data/graph/attack-graph.json` |
| Attack-path search | Done | Reachability from `web-pod` and every graph entity |
| Wildcard action/resource matching | Done | IAM action and resource pattern matching |
| Explicit deny precedence | Done | Explicit `Deny` overrides matching `Allow` |
| End-to-end pipeline | Done for modeled predictions | Environment → collect → build graph → validate modeled paths |
| Visualization | Done | Flask/Cytoscape.js interface with reachability exploration |
| Kubernetes metadata collection | Done | ServiceAccounts, workloads, Roles, RoleBindings, and Secret metadata |
| Kubernetes RBAC graph integration | Done | RBAC inheritance and Secret-read transitions are merged with IAM/S3 |
| Blast-radius metrics | Done | Per-source reachable counts and sensitive targets in `blastRadius` |
| Controlled Kubernetes scenarios | Done | Vulnerable, restricted, and mixed offline fixtures with validation |

The core implementation is documented in:

- [`README.md`](./README.md)
- [`scripts/pipeline/build-attack-graph.py`](./scripts/pipeline/build-attack-graph.py)
- [`scripts/pipeline/run-data-pipeline.ps1`](./scripts/pipeline/run-data-pipeline.ps1)

### Remaining responsibilities

#### Complete IAM policy evaluation

The following remain pending:

- IAM condition evaluation
- Conditions such as `StringEquals`, `StringLike`, `ArnLike`, and `IpAddress`
- More accurate principal and request-context handling

Conditional statements are currently excluded conservatively because the evaluator cannot yet determine whether their conditions are satisfied. Trust policies are collected and rendered as graph relationships, but observed role-assumption behavior has not yet been used to validate the modeled path.

#### Validate the graph against real actions

The graph predicts paths such as:

```text
web-pod
→ web-sa
→ cloud-twin-web-role
→ cloud-twin-api-role
→ cloud-twin-sensitive
→ sensitive-object.txt
```

Controlled actions must still be executed and compared with these predictions.

#### Improve validation reporting

The project needs structured validation records containing fields such as:

| Field | Example |
|---|---|
| Starting entity | `web-pod` |
| Predicted path | `web-pod → web-sa → web-role → api-role` |
| Attempted action | `sts:AssumeRole` |
| Expected result | Allowed |
| Observed result | Allowed |
| Pass/fail | Pass |
| Explanation | Matching allow policy and trust relationship |

#### Finalize documentation and findings

The final report still needs:

- Experimental procedure
- Observed attack results
- Predicted-versus-observed comparison
- Security findings
- Limitations
- Recommended mitigations

### Abd Alwahed status

> **Core implementation complete; validation and IAM-condition semantics remain unfinished.**

The section should not be marked 100% complete yet because the original definition of done requires validation against controlled attack execution.

## Avner Sehayek

### Completed or partially covered responsibilities

The project currently has a functional collector at [`scripts/pipeline/collect-localstack-state.ps1`](./scripts/pipeline/collect-localstack-state.ps1).

It collects:

- IAM roles
- Role trust policies
- Inline role policies
- S3 buckets
- S3 objects
- Workload-to-role mappings
- Collection timestamp and region metadata

The output is written to:

```text
data/raw/localstack-state.json
```

Therefore, the data-collection behavior exists.

### Difference from the original assignment

The original project description specifies that Avner should build the LocalStack collector using **boto3**.

The current collector does not use boto3. It is a PowerShell script that executes commands such as:

```text
docker exec cloud-twin-localstack awslocal ...
```

This is functionally useful, but it does not exactly satisfy the stated implementation requirement.

### Remaining responsibilities

#### Build a boto3-based collector

A Python collector should use boto3 clients for at least:

```python
iam.list_roles()
iam.get_role()
iam.list_role_policies()
iam.get_role_policy()
s3.list_buckets()
s3.list_objects_v2()
```

It should produce the same normalized output currently written to:

```text
data/raw/localstack-state.json
```

The existing PowerShell collector can remain as a convenience wrapper or fallback.

#### Create the attack execution checklist

The project needs executable tests for at least:

1. Public S3 access
2. Web-role access to the public bucket and object
3. Web-role attempt to assume the API role
4. API-role access to the sensitive bucket and object
5. A denied action
6. Wildcard matching behavior
7. Condition-based policy behavior once condition evaluation is implemented

#### Run attacks using explicit identities

Because LocalStack Community Edition does not automatically convert Kubernetes ServiceAccount annotations into real cloud credentials, the project needs an explicit testing method, such as:

- Temporary LocalStack IAM credentials
- `aws` or `awslocal` commands with selected credentials
- A Python boto3 test runner
- A workload-side test script
- An explicit simulation wrapper for the Kubernetes-to-role mapping

The test method must state which identity is being simulated for each action.

#### Record pass/fail results

There is currently no dedicated attack-results file or test report containing:

```text
test name
identity used
action
resource
expected result
observed result
pass/fail
evidence/error
```

The existing `validate-attack-graph.ps1` validates the presence of modeled graph paths only; it does not execute AWS or LocalStack actions and must not be treated as an observed attack report.

#### Compare observed results with graph predictions

Each controlled action should be compared with the graph:

- Predicted allowed and observed allowed → valid prediction
- Predicted denied and observed denied → valid prediction
- Mismatch → investigate the graph or test setup

#### Kubernetes attack modeling

The Kubernetes collector is implemented in
[`scripts/pipeline/collect-kubernetes-state.ps1`](./scripts/pipeline/collect-kubernetes-state.ps1).
It reads cluster metadata through `kubectl` and deliberately excludes Secret data. The graph
builder consumes the resulting snapshot through the existing pipeline and preserves the existing
IAM/S3 schema. Reproducible scenario fixtures are generated with
[`scripts/pipeline/generate-kubernetes-scenarios.py`](./scripts/pipeline/generate-kubernetes-scenarios.py)
and checked with
[`scripts/pipeline/validate-kubernetes-scenarios.py`](./scripts/pipeline/validate-kubernetes-scenarios.py).

The vulnerable and mixed scenarios predict Secret reachability from `web-pod`; the restricted
scenario does not. This validates the new Kubernetes graph transitions, but it is not a substitute
for live adversary emulation. OSAKA is now the primary visualization integration: its Neo4j
database receives the Kubernetes collection first, then the Cloud Twin IAM/S3 graph, catalog
findings, and predicted paths. Caldera remains an optional follow-up for live adversary emulation.

### Avner status

> **Collector functionality exists, but the required boto3 implementation, attack checklist, controlled execution, and pass/fail validation are not complete.**

## Remaining critical work

The most important unfinished part is:

```text
Predicted path
        vs.
Actual controlled attack result
```

The remaining work is:

1. Add or finish the boto3-based collector if required by the assignment.
2. Add controlled attack scripts.
3. Execute allowed and denied actions using explicitly documented identities.
4. Record the results.
5. Compare results with graph predictions.
6. Implement IAM condition evaluation.
7. Document final findings and mismatches.

## Final status summary

| Person | Status |
|---|---|
| **Abd Alwahed** | Core engineering work complete for the prototype; IAM conditions and empirical validation remain |
| **Avner** | PowerShell collector behavior exists; the boto3 implementation and attack-validation work remain |
| **Dallas** | Research/background and final narrative work remain outside the current implementation scope |

## Main project conclusion

The environment, collector pipeline, graph model, attack-path engine, and visualization are working as a prototype. The project becomes fully complete when the predicted attack paths are tested against controlled actions, condition semantics are addressed, and the results are documented.
