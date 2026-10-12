import json
import subprocess
import time
from urllib.error import URLError
from urllib.request import urlopen
from pathlib import Path

from flask import Flask, jsonify, render_template


PROJECT_ROOT = Path(__file__).resolve().parent.parent
GRAPH_PATH = PROJECT_ROOT / "data" / "graph" / "attack-graph.json"
PIPELINE_PATH = PROJECT_ROOT / "scripts" / "pipeline" / "run-data-pipeline.ps1"

app = Flask(__name__)
app.config["SEND_FILE_MAX_AGE_DEFAULT"] = 0


def load_graph():
    if not GRAPH_PATH.exists():
        raise FileNotFoundError(
            f"Attack graph not found at {GRAPH_PATH}. Run the data pipeline first."
        )
    return json.loads(GRAPH_PATH.read_text(encoding="utf-8"))


def graph_metadata():
    return {"updatedAt": GRAPH_PATH.stat().st_mtime_ns}


def ensure_localstack():
    try:
        result = subprocess.run(
            [
                "docker",
                "compose",
                "-f",
                str(PROJECT_ROOT / "docker" / "docker-compose.localstack.yml"),
                "up",
                "-d",
            ],
            cwd=PROJECT_ROOT,
            capture_output=True,
            text=True,
            check=False,
        )
    except OSError as error:
        raise RuntimeError(f"Docker could not be started: {error}") from error

    if result.returncode != 0:
        details = (result.stderr or result.stdout).strip()
        raise RuntimeError(f"Docker could not start LocalStack: {details}")

    health_url = "http://localhost:4566/_localstack/health"
    for _ in range(45):
        try:
            with urlopen(health_url, timeout=2) as response:
                health = json.loads(response.read())
                services = health.get("services", {})
                if services.get("iam") in {"available", "running"} and services.get("s3") in {"available", "running"}:
                    return
        except (URLError, TimeoutError):
            pass
        time.sleep(1)
    raise RuntimeError(
        "LocalStack did not become available at http://localhost:4566. "
        "Check Docker Desktop and the cloud-twin-localstack container."
    )


@app.get("/")
def index():
    return render_template("index.html")


@app.get("/api/graph")
def graph():
    payload = load_graph()
    payload["_metadata"] = graph_metadata()
    return jsonify(payload)


@app.post("/api/regenerate")
def regenerate():
    try:
        ensure_localstack()
    except RuntimeError as error:
        return jsonify({"error": str(error)}), 503

    provision_result = subprocess.run(
        [
            "powershell",
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            str(PROJECT_ROOT / "scripts" / "localstack" / "provision-localstack.ps1"),
        ],
        cwd=PROJECT_ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    if provision_result.returncode != 0:
        details = (provision_result.stderr or provision_result.stdout).strip()
        return jsonify({"error": f"LocalStack fixture provisioning failed: {details}"}), 500

    result = subprocess.run(
        [
            "powershell",
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            str(PIPELINE_PATH),
        ],
        cwd=PROJECT_ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        details = (result.stderr or result.stdout).strip()
        return jsonify({"error": f"Graph regeneration failed: {details}"}), 500

    payload = load_graph()
    payload["_metadata"] = graph_metadata()
    return jsonify({"graph": payload, "message": "Graph regenerated from LocalStack state."})


if __name__ == "__main__":
    app.run(host="127.0.0.1", port=5000, debug=False)
