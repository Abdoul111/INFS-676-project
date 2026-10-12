import argparse
import json
import fnmatch
from collections import deque
from pathlib import Path


def add_edge(edges, source, relation, target, **attributes):
    edges.append({"source": source, "relation": relation, "target": target, **attributes})


def policy_statements(role):
    for policy in role.get("inlinePolicies", []):
        document = policy.get("document", {})
        statements = document.get("Statement", [])
        if isinstance(statements, dict):
            statements = [statements]
        for statement in statements:
            yield policy["name"], statement


def values(value):
    return value if isinstance(value, list) else [value]


def matches(pattern, value):
    return pattern == "*" or fnmatch.fnmatchcase(value, pattern)


def statement_matches(statement, action, resource):
    actions = values(statement.get("Action", []))
    resources = values(statement.get("Resource", []))
    return any(matches(pattern, action) for pattern in actions) and any(
        matches(pattern, resource) for pattern in resources
    )


def permission_allowed(statements, action, resource):
    matching = [
        statement
        for statement in statements
        if statement_matches(statement, action, resource)
    ]
    if any(statement.get("Effect") == "Deny" for statement in matching):
        return False
    return any(
        statement.get("Effect") == "Allow" and not statement.get("Condition")
        for statement in matching
    )


def build_graph(state):
    nodes = []
    edges = []
    roles_by_arn = {role["roleArn"]: role for role in state["roles"]}

    for mapping in state["identityMappings"]:
        workload_id = f'workload:{mapping["workload"]}'
        service_account_id = f'service-account:{mapping["namespace"]}:{mapping["serviceAccount"]}'
        role_id = f'iam-role:{mapping["roleArn"]}'
        nodes.extend(
            [
                {"id": workload_id, "type": "workload", "name": mapping["workload"], "tier": "public" if mapping["workload"] == "web-pod" else "private"},
                {"id": service_account_id, "type": "service_account", "name": mapping["serviceAccount"]},
                {"id": role_id, "type": "iam_role", "name": mapping["roleArn"].rsplit("/", 1)[-1], "arn": mapping["roleArn"]},
            ]
        )
        add_edge(edges, workload_id, "uses_service_account", service_account_id)
        add_edge(edges, service_account_id, "maps_to_role", role_id)

    for role in state["roles"]:
        role_id = f'iam-role:{role["roleArn"]}'
        role_statements = list(policy_statements(role))
        for statement in role.get("trustPolicy", {}).get("Statement", []):
            for principal_type, principal_value in statement.get("Principal", {}).items():
                for principal in values(principal_value):
                    principal_id = f"principal:{principal}"
                    nodes.append({"id": principal_id, "type": "principal", "name": principal})
                    add_edge(edges, role_id, "trusts", principal_id, action=statement.get("Action"))
        for policy_name, statement in role_statements:
            for action in values(statement.get("Action", [])):
                for resource in values(statement.get("Resource", [])):
                    permission_id = f"permission:{role['roleArn']}:{policy_name}:{action}:{resource}"
                    nodes.append({"id": permission_id, "type": "permission", "effect": statement.get("Effect"), "action": action, "resource": resource, "policy": policy_name})
                    if statement.get("Effect") == "Allow" and permission_allowed(
                        [candidate for _, candidate in role_statements], action, resource
                    ):
                        add_edge(edges, role_id, "has_permission", permission_id, action=action, resource=resource)
                    if (
                        statement.get("Effect") == "Allow"
                        and permission_allowed(
                            [candidate for _, candidate in role_statements], action, resource
                        )
                        and any(matches(action_pattern, "sts:AssumeRole") for action_pattern in values(statement.get("Action", [])))
                        and resource in roles_by_arn
                    ):
                        add_edge(edges, role_id, "can_assume_role", f"iam-role:{resource}", action=action, resource=resource)
                    if (
                        statement.get("Effect") == "Allow"
                        and permission_allowed(
                            [candidate for _, candidate in role_statements], action, resource
                        )
                        and resource.startswith("arn:aws:s3:::")
                    ):
                        bucket_name = resource.split(":::")[1].split("/", 1)[0]
                        bucket_id = f"s3-bucket:{bucket_name}"
                        nodes.append({"id": bucket_id, "type": "s3_bucket", "name": bucket_name})
                        add_edge(edges, role_id, "can_access", bucket_id, action=action, effect=statement.get("Effect"), resource=resource)

    for bucket in state["buckets"]:
        bucket_id = f's3-bucket:{bucket["name"]}'
        nodes.append({"id": bucket_id, "type": "s3_bucket", "name": bucket["name"]})
        for object_data in bucket.get("objects", []):
            object_id = f's3-object:{bucket["name"]}/{object_data["key"]}'
            nodes.append({"id": object_id, "type": "s3_object", "name": object_data["key"], "bucket": bucket["name"]})
            add_edge(edges, bucket_id, "contains", object_id)

    unique_nodes = {node["id"]: node for node in nodes}
    unique_edges = {(edge["source"], edge["relation"], edge["target"], edge.get("action"), edge.get("resource")): edge for edge in edges}
    return {"nodes": list(unique_nodes.values()), "edges": list(unique_edges.values())}


def find_paths(graph, start_id, max_depth):
    adjacency = {}
    for edge in graph["edges"]:
        adjacency.setdefault(edge["source"], []).append(edge)
    paths = []
    queue = deque([(start_id, [start_id], [])])
    while queue:
        current, node_path, edge_path = queue.popleft()
        if len(edge_path) >= max_depth:
            continue
        for edge in adjacency.get(current, []):
            target = edge["target"]
            if target in node_path:
                continue
            new_nodes = node_path + [target]
            new_edges = edge_path + [edge]
            if target.startswith(("s3-object:", "s3-bucket:", "iam-role:", "workload:", "service-account:")):
                paths.append({"nodes": new_nodes, "edges": new_edges})
            queue.append((target, new_nodes, new_edges))
    return paths


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("state", type=Path)
    parser.add_argument("--output", type=Path, default=Path("data/graph/attack-graph.json"))
    args = parser.parse_args()
    state = json.loads(args.state.read_text(encoding="utf-8-sig"))
    graph = build_graph(state)
    paths = find_paths(graph, "workload:web-pod", 8)
    unique_paths = {}
    for path in paths:
        key = tuple(path["nodes"])
        unique_paths[key] = path
    graph["predictedPaths"] = list(unique_paths.values())
    graph["reachability"] = {}
    for node in graph["nodes"]:
        source = node["id"]
        source_paths = find_paths(graph, source, 8)
        unique_source_paths = {
            tuple(path["nodes"]): path for path in source_paths
        }
        graph["reachability"][source] = {
            "reachableNodes": sorted(
                {path["nodes"][-1] for path in unique_source_paths.values()}
            ),
            "paths": list(unique_source_paths.values()),
        }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(graph, indent=2), encoding="utf-8")
    print(f"Built graph with {len(graph['nodes'])} nodes, {len(graph['edges'])} edges, and {len(graph['predictedPaths'])} predicted paths.")
    for path in graph["predictedPaths"]:
        print(" -> ".join(path["nodes"]))


if __name__ == "__main__":
    main()
