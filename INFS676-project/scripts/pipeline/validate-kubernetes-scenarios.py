import argparse
import importlib.util
import json
from pathlib import Path


def load_builder(path):
    spec = importlib.util.spec_from_file_location("attack_graph_builder", path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Unable to load graph builder: {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("state", type=Path)
    parser.add_argument(
        "--scenarios", type=Path, default=Path("data/scenarios")
    )
    parser.add_argument(
        "--builder",
        type=Path,
        default=Path("scripts/pipeline/build-attack-graph.py"),
    )
    args = parser.parse_args()
    builder = load_builder(args.builder)
    base_state = json.loads(args.state.read_text(encoding="utf-8-sig"))
    expected = {"vulnerable": True, "restricted": False, "mixed": True}

    for name, should_reach_secret in expected.items():
        scenario_state = json.loads(
            (args.scenarios / name / "kubernetes-state.json").read_text(
                encoding="utf-8"
            )
        )
        state = dict(base_state)
        state["kubernetes"] = scenario_state["kubernetes"]
        graph = builder.build_graph(state)
        paths = builder.find_paths(graph, "workload:cloud-twin:web-pod", 8)
        reaches_secret = any(
            any(node.startswith("secret:") for node in path["nodes"])
            for path in paths
        )
        if reaches_secret != should_reach_secret:
            raise SystemExit(
                f"FAIL: {name} expected secret reachability "
                f"{should_reach_secret}, observed {reaches_secret}"
            )
        print(
            f"PASS: {name} secret reachability={reaches_secret}; "
            f"paths={len(paths)}"
        )


if __name__ == "__main__":
    main()
