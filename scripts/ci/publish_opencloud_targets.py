#!/usr/bin/env python3
import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path


def die(message: str) -> None:
    print(message, file=sys.stderr)
    raise SystemExit(1)


def load_targets(manifest_path: Path):
    with manifest_path.open("r", encoding="utf-8") as handle:
        payload = json.load(handle)
    targets = payload.get("targets")
    if not isinstance(targets, list) or not targets:
        die("Prepared manifest requires a non-empty 'targets' list.")
    for entry in targets:
        if not isinstance(entry, dict):
            die("Each target entry must be an object.")
        if not entry.get("name"):
            die("Each target entry requires 'name'.")
        if entry.get("placeId") in (None, ""):
            die("Each target entry requires 'placeId'.")
        if not entry.get("artifactPath"):
            die("Each target entry requires 'artifactPath'.")
    return targets


def parse_version_number(response_text: str):
    try:
        data = json.loads(response_text)
    except json.JSONDecodeError:
        return None
    value = data.get("versionNumber")
    if isinstance(value, int):
        return value
    return None


def publish_target(
    *,
    universe_id: str,
    api_key: str,
    place_id: int,
    artifact_path: Path,
    name: str,
    max_attempts: int,
) -> None:
    if not artifact_path.is_file():
        die(f"Target '{name}' artifact does not exist: {artifact_path}")

    endpoint = (
        f"https://apis.roblox.com/universes/v1/{universe_id}/places/{place_id}/versions"
        "?versionType=Published"
    )
    body = artifact_path.read_bytes()
    headers = {
        "x-api-key": api_key,
        "Content-Type": "application/xml",
    }

    for attempt in range(1, max_attempts + 1):
        request = urllib.request.Request(endpoint, method="POST", headers=headers, data=body)
        try:
            with urllib.request.urlopen(request, timeout=180) as response:
                response_body = response.read().decode("utf-8", errors="replace")
                version_number = parse_version_number(response_body)
                if version_number is not None:
                    print(
                        f"Published {name} (placeId={place_id}) to version {version_number} "
                        f"from {artifact_path}."
                    )
                else:
                    print(
                        f"Published {name} (placeId={place_id}) from {artifact_path}. "
                        f"Response: {response_body}"
                    )
                return
        except urllib.error.HTTPError as exc:
            response_body = exc.read().decode("utf-8", errors="replace")
            if exc.code == 409 and attempt < max_attempts:
                wait_seconds = attempt * 20
                print(
                    f"Publish conflict for {name} (placeId={place_id}) "
                    f"attempt {attempt}/{max_attempts}. Retrying in {wait_seconds}s."
                )
                print(f"Response: {response_body}")
                time.sleep(wait_seconds)
                continue
            die(
                f"Publish failed for {name} (placeId={place_id}) "
                f"with HTTP {exc.code} on attempt {attempt}/{max_attempts}. "
                f"Response: {response_body}"
            )
        except urllib.error.URLError as exc:
            if attempt < max_attempts:
                wait_seconds = attempt * 10
                print(
                    f"Network error for {name} (placeId={place_id}) "
                    f"attempt {attempt}/{max_attempts}: {exc}. Retrying in {wait_seconds}s."
                )
                time.sleep(wait_seconds)
                continue
            die(
                f"Network error for {name} (placeId={place_id}) "
                f"on attempt {attempt}/{max_attempts}: {exc}"
            )


def main() -> None:
    parser = argparse.ArgumentParser(description="Publish prepared place artifacts using Roblox Open Cloud.")
    parser.add_argument("--manifest", required=True, help="Prepared manifest JSON from prepare_place_publish.py.")
    parser.add_argument("--universe-id", required=True, help="Roblox universe ID.")
    parser.add_argument("--api-key", required=True, help="Roblox Open Cloud API key.")
    parser.add_argument("--max-attempts", type=int, default=6, help="Max attempts per target (default 6).")
    args = parser.parse_args()

    if args.max_attempts < 1:
        die("--max-attempts must be >= 1")

    workspace_root = Path(os.getcwd()).resolve()
    manifest_path = (workspace_root / args.manifest).resolve()
    if not manifest_path.is_file():
        die(f"Prepared manifest not found: {args.manifest}")

    targets = load_targets(manifest_path)
    for target in targets:
        name = str(target["name"])
        place_id = int(target["placeId"])
        artifact_path = (workspace_root / str(target["artifactPath"])).resolve()
        publish_target(
            universe_id=str(args.universe_id),
            api_key=str(args.api_key),
            place_id=place_id,
            artifact_path=artifact_path,
            name=name,
            max_attempts=args.max_attempts,
        )


if __name__ == "__main__":
    main()
