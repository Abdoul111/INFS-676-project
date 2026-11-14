import argparse
import json
import uuid
from pathlib import Path

from neo4j_http import Neo4jHttpClient


def main():
    parser = argparse.ArgumentParser(description="Publish the project NeoDash dashboard.")
    parser.add_argument("dashboard", type=Path)
    parser.add_argument("--neo4j-url", default="http://127.0.0.1:7474")
    parser.add_argument("--username", default="neo4j")
    parser.add_argument("--password", required=True)
    args = parser.parse_args()

    dashboard = json.loads(args.dashboard.read_text(encoding="utf-8"))
    client = Neo4jHttpClient(args.neo4j_url, args.username, args.password)
    client.run(
        """
        MERGE (n:_Neodash_Dashboard {title: $title})
        SET n.uuid = $uuid,
            n.version = $version,
            n.user = $user,
            n.content = $content,
            n.date = datetime()
        """,
        {
            "title": dashboard["title"],
            "uuid": str(uuid.uuid4()),
            "version": dashboard["version"],
            "user": args.username,
            "content": json.dumps(dashboard, separators=(",", ":")),
        },
    )
    print(f"Published dashboard: {dashboard['title']}")


if __name__ == "__main__":
    main()
