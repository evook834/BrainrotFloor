#!/usr/bin/env python3
import argparse
import copy
import json
import os
import sys
import uuid
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Dict, List, Optional, Set, Tuple


ROLE_DEFAULTS = {
    "lobby": {
        "projectFile": "game/places/lobby/default.project.json",
        "buildArtifact": "artifacts/lobby-place.rbxlx",
    },
    "match": {
        "projectFile": "game/places/match/default.project.json",
        "buildArtifact": "artifacts/match-place.rbxlx",
    },
}


def die(message: str) -> None:
    print(message, file=sys.stderr)
    raise SystemExit(1)


def get_item_name(item: ET.Element) -> Optional[str]:
    props = item.find("Properties")
    if props is None:
        return None
    for child in props:
        if child.tag == "string" and child.get("name") == "Name":
            return child.text or ""
    return None


def iter_child_items(item: ET.Element):
    for child in item:
        if child.tag == "Item":
            yield child


def build_item_index(root: ET.Element) -> Dict[str, ET.Element]:
    index: Dict[str, ET.Element] = {}

    def walk(item: ET.Element, path: str) -> None:
        name = get_item_name(item)
        if name is None:
            return
        current_path = name if not path else f"{path}/{name}"
        index[current_path] = item
        for child in iter_child_items(item):
            walk(child, current_path)

    for top_item in root:
        if top_item.tag == "Item":
            walk(top_item, "")
    return index


def collect_referents(root: ET.Element) -> Set[str]:
    referents: Set[str] = set()
    for elem in root.iter():
        ref = elem.get("referent")
        if ref:
            referents.add(ref)
    return referents


def unique_referent(existing: Set[str]) -> str:
    while True:
        candidate = "RBX" + uuid.uuid4().hex.upper()
        if candidate not in existing:
            existing.add(candidate)
            return candidate


def remap_referents(subtree: ET.Element, existing: Set[str]) -> None:
    remap: Dict[str, str] = {}

    for elem in subtree.iter():
        ref = elem.get("referent")
        if not ref:
            continue
        if ref not in remap:
            remap[ref] = unique_referent(existing)
        elem.set("referent", remap[ref])

    if not remap:
        return

    for elem in subtree.iter():
        if elem.tag == "Ref" and elem.text in remap:
            elem.text = remap[elem.text]


def parse_project_managed_paths(project_file: Path) -> List[str]:
    with project_file.open("r", encoding="utf-8") as handle:
        project = json.load(handle)

    tree = project.get("tree")
    if not isinstance(tree, dict):
        die(f"Invalid project file (missing tree object): {project_file}")

    discovered: List[str] = []

    def walk(node: dict, path_segments: List[str]) -> None:
        if "$path" in node and path_segments:
            discovered.append("/".join(path_segments))

        for key, value in node.items():
            if key.startswith("$"):
                continue
            if isinstance(value, dict):
                walk(value, path_segments + [key])

    walk(tree, [])

    # Keep only top-most managed paths. If parent is managed, child is already covered.
    discovered = sorted(set(discovered), key=lambda p: (p.count("/"), p))
    filtered: List[str] = []
    for path in discovered:
        if any(path == existing or path.startswith(existing + "/") for existing in filtered):
            continue
        filtered.append(path)

    if not filtered:
        die(f"No managed paths discovered from project file: {project_file}")

    return filtered


def remove_child_item(parent: ET.Element, child_name: str) -> None:
    for child in list(parent):
        if child.tag != "Item":
            continue
        if get_item_name(child) == child_name:
            parent.remove(child)
            return


def append_child_item(parent: ET.Element, child: ET.Element) -> None:
    parent.append(child)


def merge_snapshot(
    *,
    base_snapshot: Path,
    build_snapshot: Path,
    project_file: Path,
    output_snapshot: Path,
) -> None:
    managed_paths = parse_project_managed_paths(project_file)

    base_tree = ET.parse(base_snapshot)
    build_tree = ET.parse(build_snapshot)
    base_root = base_tree.getroot()
    build_root = build_tree.getroot()

    base_index = build_item_index(base_root)
    build_index = build_item_index(build_root)
    referents = collect_referents(base_root)

    for managed_path in managed_paths:
        if "/" not in managed_path:
            die(f"Managed path '{managed_path}' is a root service; refusing full-service replacement.")

        parent_path, child_name = managed_path.rsplit("/", 1)
        base_parent = base_index.get(parent_path)
        if base_parent is None:
            die(
                "Base snapshot is missing required parent path "
                f"'{parent_path}' while merging '{managed_path}'."
            )

        # Remove managed node from base before importing overlay node.
        remove_child_item(base_parent, child_name)

        build_item = build_index.get(managed_path)
        if build_item is None:
            # Overlay has no node at this path, so this managed node stays removed.
            continue

        cloned = copy.deepcopy(build_item)
        remap_referents(cloned, referents)
        append_child_item(base_parent, cloned)

        # Rebuild index entries below parent for subsequent paths.
        base_index = build_item_index(base_root)

    output_snapshot.parent.mkdir(parents=True, exist_ok=True)
    ET.register_namespace("xsi", "http://www.w3.org/2001/XMLSchema-instance")
    ET.register_namespace("xmime", "http://www.w3.org/2005/05/xmlmime")
    base_tree.write(output_snapshot, encoding="utf-8", xml_declaration=False)


def resolve_target(
    target: dict,
    workspace_root: Path,
) -> Tuple[str, int, Path, Path, Path]:
    name = target.get("name")
    if not isinstance(name, str) or not name:
        die("Each target requires a non-empty string 'name'.")

    role = target.get("role")
    defaults = ROLE_DEFAULTS.get(role, {})

    place_id_raw = target.get("placeId")
    if place_id_raw is None:
        die(f"Target '{name}' is missing required 'placeId'.")
    try:
        place_id = int(place_id_raw)
    except (TypeError, ValueError):
        die(f"Target '{name}' has invalid placeId: {place_id_raw}")
    if place_id <= 0:
        die(f"Target '{name}' has non-positive placeId: {place_id}")

    base_snapshot = target.get("baseSnapshot")
    if not isinstance(base_snapshot, str) or not base_snapshot:
        die(f"Target '{name}' is missing required 'baseSnapshot'.")

    project_file = target.get("projectFile", defaults.get("projectFile"))
    build_artifact = target.get("buildArtifact", defaults.get("buildArtifact"))
    if not isinstance(project_file, str) or not project_file:
        die(f"Target '{name}' requires 'projectFile' or recognized 'role'.")
    if not isinstance(build_artifact, str) or not build_artifact:
        die(f"Target '{name}' requires 'buildArtifact' or recognized 'role'.")

    base_snapshot_path = (workspace_root / base_snapshot).resolve()
    project_file_path = (workspace_root / project_file).resolve()
    build_artifact_path = (workspace_root / build_artifact).resolve()

    if not base_snapshot_path.is_file():
        die(f"Target '{name}' baseSnapshot does not exist: {base_snapshot}")
    if not project_file_path.is_file():
        die(f"Target '{name}' projectFile does not exist: {project_file}")
    if not build_artifact_path.is_file():
        die(f"Target '{name}' buildArtifact does not exist: {build_artifact}")

    return name, place_id, base_snapshot_path, project_file_path, build_artifact_path


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Merge Rojo-built code artifacts into base place snapshots for Open Cloud publishing."
    )
    parser.add_argument("--manifest", required=True, help="Path to publish targets JSON manifest.")
    parser.add_argument("--output-dir", required=True, help="Directory to write merged .rbxlx files.")
    parser.add_argument(
        "--prepared-manifest",
        required=True,
        help="Path to write resolved publish manifest containing output artifact paths.",
    )
    args = parser.parse_args()

    workspace_root = Path(os.getcwd()).resolve()
    manifest_path = (workspace_root / args.manifest).resolve()
    if not manifest_path.is_file():
        die(f"Manifest file not found: {args.manifest}")

    with manifest_path.open("r", encoding="utf-8") as handle:
        manifest = json.load(handle)

    targets = manifest.get("targets")
    if not isinstance(targets, list) or not targets:
        die("Manifest requires non-empty 'targets' list.")

    output_dir = (workspace_root / args.output_dir).resolve()
    output_dir.mkdir(parents=True, exist_ok=True)

    prepared_targets = []

    for target in targets:
        if not isinstance(target, dict):
            die("Each manifest target must be an object.")

        name, place_id, base_snapshot, project_file, build_artifact = resolve_target(target, workspace_root)
        output_snapshot = output_dir / f"{name}.rbxlx"

        print(f"Merging target '{name}' (placeId={place_id})...")
        merge_snapshot(
            base_snapshot=base_snapshot,
            build_snapshot=build_artifact,
            project_file=project_file,
            output_snapshot=output_snapshot,
        )
        prepared_targets.append(
            {
                "name": name,
                "placeId": place_id,
                "artifactPath": os.path.relpath(output_snapshot, workspace_root),
            }
        )

    prepared_manifest_path = (workspace_root / args.prepared_manifest).resolve()
    prepared_manifest_path.parent.mkdir(parents=True, exist_ok=True)
    with prepared_manifest_path.open("w", encoding="utf-8") as handle:
        json.dump({"targets": prepared_targets}, handle, indent=2)
        handle.write("\n")

    print(f"Wrote prepared publish manifest: {os.path.relpath(prepared_manifest_path, workspace_root)}")


if __name__ == "__main__":
    main()
