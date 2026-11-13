import argparse
import json
from pathlib import Path


def scenario(name):
    rules = {
        "vulnerable": [
            {"apiGroups": [""], "resources": ["secrets"], "verbs": ["get", "list"]}
        ],
        "restricted": [
            {"apiGroups": [""], "resources": ["configmaps"], "verbs": ["get"]}
        ],
        "mixed": [
            {"apiGroups": [""], "resources": ["secrets"], "verbs": ["get"]}
        ],
    }
    return {
        "collectedAt": "scenario",
        "context": "scenario",
        "kubernetes": {
            "serviceAccounts": [
                {"name": "web-sa", "namespace": "cloud-twin", "annotations": {}},
                {"name": "api-sa", "namespace": "cloud-twin", "annotations": {}},
            ],
            "workloads": [
                {
                    "name": "web-pod",
                    "namespace": "cloud-twin",
                    "serviceAccount": "web-sa",
                    "tier": "public",
                },
                {
                    "name": "api-pod",
                    "namespace": "cloud-twin",
                    "serviceAccount": "api-sa",
                    "tier": "private",
                },
            ],
            "roles": [
                {
                    "kind": "Role",
                    "name": f"{name}-role",
                    "namespace": "cloud-twin",
                    "rules": rules[name],
                }
            ],
            "roleBindings": [
                {
                    "name": f"{name}-binding",
                    "namespace": "cloud-twin",
                    "roleRef": {"kind": "Role", "name": f"{name}-role"},
                    "subjects": [
                        {
                            "kind": "ServiceAccount",
                            "name": "web-sa",
                            "namespace": "cloud-twin",
                        }
                    ],
                }
            ],
            "secrets": [
                {
                    "name": "sensitive-config",
                    "namespace": "cloud-twin",
                    "type": "Opaque",
                }
            ],
        },
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("data/scenarios"),
        help="Directory receiving one JSON snapshot per scenario",
    )
    args = parser.parse_args()
    for name in ("vulnerable", "restricted", "mixed"):
        scenario_dir = args.output / name
        scenario_dir.mkdir(parents=True, exist_ok=True)
        path = scenario_dir / "kubernetes-state.json"
        path.write_text(json.dumps(scenario(name), indent=2), encoding="utf-8")
        print(f"Generated {name}: {path}")


if __name__ == "__main__":
    main()
