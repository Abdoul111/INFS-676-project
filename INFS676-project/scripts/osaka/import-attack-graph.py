import argparse
import json
from pathlib import Path

from neo4j_http import Neo4jHttpClient


def property_value(value):
    if isinstance(value, (dict, list)) and any(
        isinstance(item, dict) for item in (value.values() if isinstance(value, dict) else value)
    ):
        return json.dumps(value, sort_keys=True)
    return value


def normalized_properties(value):
    return {
        key: property_value(item)
        for key, item in value.items()
        if key != "id" and item is not None
    }


def matches_finding(finding, node=None, edge=None):
    matcher = finding.get("match", {})
    if node is not None:
        if not matcher.get("nodeType"):
            return False
        if matcher.get("nodeType") and node.get("type") != matcher["nodeType"]:
            return False
        if matcher.get("propertyContains"):
            key, expected = matcher["propertyContains"]
            if expected not in json.dumps(node.get(key, ""), sort_keys=True):
                return False
    if edge is not None:
        if not matcher.get("edgeRelation"):
            return False
        if matcher.get("edgeRelation") and edge.get("relation") != matcher["edgeRelation"]:
            return False
        target = edge.get("_target", {})
        if matcher.get("targetType") and target.get("type") != matcher["targetType"]:
            return False
        if matcher.get("targetNameContains") and matcher["targetNameContains"] not in target.get(
            "name", ""
        ):
            return False
    return bool(matcher.get("nodeType") or matcher.get("edgeRelation"))


def create_finding(client, definition, evidence):
    client.run(
        """
        MERGE (f:CloudTwinFinding {findingId: $findingId, evidenceId: $evidenceId})
        SET f.title = $title,
            f.severity = $severity,
            f.remediation = $remediation,
            f.blockingAction = $blockingAction,
            f.source = "catalog",
            f.evidence = $evidence
        """,
        {
            "findingId": definition["id"],
            "evidenceId": evidence["evidenceId"],
            "title": definition["title"],
            "severity": definition["severity"],
            "remediation": definition["remediation"],
            "blockingAction": definition["blockingAction"],
            "evidence": json.dumps(evidence, sort_keys=True),
        },
    )


def main():
    parser = argparse.ArgumentParser(description="Import the unified graph into OSAKA Neo4j.")
    parser.add_argument("graph", type=Path)
    parser.add_argument("--catalog", type=Path, required=True)
    parser.add_argument("--neo4j-url", default="http://127.0.0.1:7474")
    parser.add_argument("--username", default="neo4j")
    parser.add_argument("--password", required=True)
    args = parser.parse_args()

    graph = json.loads(args.graph.read_text(encoding="utf-8"))
    catalog = json.loads(args.catalog.read_text(encoding="utf-8"))["findings"]
    client = Neo4jHttpClient(args.neo4j_url, args.username, args.password)

    client.run("MATCH (n:CloudTwinNode) DETACH DELETE n")
    client.run("MATCH (f:CloudTwinFinding) DETACH DELETE f")
    client.run("MATCH (p:CloudTwinPath) DETACH DELETE p")

    nodes = {node["id"]: node for node in graph.get("nodes", [])}
    for node in nodes.values():
        client.run(
            """
            MERGE (n:CloudTwinNode {id: $id})
            SET n += $properties
            """,
            {
                "id": node["id"],
                "properties": {
                    **normalized_properties(node),
                    "sourceSystem": "cloud-twin",
                },
            },
        )

    for edge in graph.get("edges", []):
        source = nodes.get(edge["source"], {})
        target = nodes.get(edge["target"], {})
        client.run(
            """
            MATCH (source:CloudTwinNode {id: $sourceId})
            MATCH (target:CloudTwinNode {id: $targetId})
            MERGE (source)-[r:CloudTwinEdge {relation: $relation}]->(target)
            SET r += $properties
            """,
            {
                "sourceId": edge["source"],
                "targetId": edge["target"],
                "relation": edge["relation"],
                "properties": normalized_properties(edge),
            },
        )
        for definition in catalog:
            if matches_finding(definition, edge={**edge, "_target": target}):
                create_finding(
                    client,
                    definition,
                    {
                        "evidenceId": f"{edge['source']}->{edge['target']}:{edge['relation']}",
                        "source": edge["source"],
                        "target": edge["target"],
                        "relation": edge["relation"],
                    },
                )

    for node in nodes.values():
        for definition in catalog:
            if matches_finding(definition, node=node):
                create_finding(
                    client,
                    definition,
                    {
                        "evidenceId": node["id"],
                        "node": node["id"],
                        "type": node.get("type"),
                    },
                )

    for index, path in enumerate(graph.get("predictedPaths", []), start=1):
        path_nodes = path.get("nodes", [])
        client.run(
            """
            CREATE (p:CloudTwinPath {
                pathId: $pathId,
                nodeIds: $nodeIds,
                edgeCount: $edgeCount,
                sourceId: $sourceId,
                targetId: $targetId,
                targetType: $targetType
            })
            """,
            {
                "pathId": f"predicted-{index}",
                "nodeIds": json.dumps(path_nodes),
                "edgeCount": len(path.get("edges", [])),
                "sourceId": path_nodes[0] if path_nodes else "",
                "targetId": path_nodes[-1] if path_nodes else "",
                "targetType": nodes.get(path_nodes[-1], {}).get("type", "") if path_nodes else "",
            },
        )

    client.run(
        """
        MERGE (s:CloudTwinSnapshot {name: "current"})
        SET s.updatedAt = datetime(),
            s.nodeCount = $nodeCount,
            s.edgeCount = $edgeCount,
            s.pathCount = $pathCount
        """,
        {
            "nodeCount": len(nodes),
            "edgeCount": len(graph.get("edges", [])),
            "pathCount": len(graph.get("predictedPaths", [])),
        },
    )
    print(
        f"Imported {len(nodes)} nodes, {len(graph.get('edges', []))} edges, "
        f"and {len(graph.get('predictedPaths', []))} predicted paths."
    )


if __name__ == "__main__":
    main()
