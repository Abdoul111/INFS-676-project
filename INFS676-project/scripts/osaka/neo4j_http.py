import base64
import json
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


class Neo4jHttpClient:
    def __init__(self, url, username, password, database="neo4j"):
        self.url = url.rstrip("/") + f"/db/{database}/tx/commit"
        token = base64.b64encode(f"{username}:{password}".encode("utf-8")).decode("ascii")
        self.headers = {
            "Authorization": f"Basic {token}",
            "Content-Type": "application/json",
            "Accept": "application/json",
        }

    def run(self, statement, parameters=None):
        body = json.dumps(
            {
                "statements": [
                    {
                        "statement": statement,
                        "parameters": parameters or {},
                    }
                ]
            }
        ).encode("utf-8")
        request = Request(self.url, data=body, headers=self.headers, method="POST")
        try:
            with urlopen(request, timeout=30) as response:
                payload = json.loads(response.read().decode("utf-8"))
        except (HTTPError, URLError) as error:
            raise RuntimeError(f"Neo4j HTTP request failed: {error}") from error

        errors = payload.get("errors", [])
        if errors:
            messages = "; ".join(
                f"{item.get('code', 'unknown')}: {item.get('message', 'unknown error')}"
                for item in errors
            )
            raise RuntimeError(f"Neo4j query failed: {messages}")
        return payload.get("results", [])
