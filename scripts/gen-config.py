#!/usr/bin/env python3

"""Generate deterministic Talos control-plane machine configurations."""

from __future__ import annotations

import argparse
import subprocess
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate Talos control-plane configurations."
    )
    parser.add_argument("cluster_name")
    parser.add_argument("cluster_url")
    parser.add_argument(
        "--config-dir",
        type=Path,
        default=Path("config"),
        help="Directory containing the shared and per-node patches.",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path("temp"),
        help="Directory for generated machine configurations.",
    )
    parser.add_argument(
        "--secrets",
        type=Path,
        default=Path("secrets.yaml"),
        help="Existing Talos secrets file; never generate a new one here.",
    )
    parser.add_argument(
        "--kubernetes-version",
        default="1.36.3",
        help="Kubernetes version embedded in generated machine configs.",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    config_dir = args.config_dir
    common_patch = config_dir / "control-plane-common.yaml"
    node_patches = sorted(config_dir.glob("talos-ctrl-*.yaml"))

    if not common_patch.is_file():
        raise SystemExit(f"missing shared patch: {common_patch}")
    if not node_patches:
        raise SystemExit(f"no control-plane patches found in {config_dir}")
    if not args.secrets.is_file():
        raise SystemExit(f"missing secrets file: {args.secrets}")

    args.output_dir.mkdir(parents=True, exist_ok=True)

    for node_patch in node_patches:
        output_path = args.output_dir / node_patch.name
        command = [
            "talosctl",
            "gen",
            "config",
            args.cluster_name,
            args.cluster_url,
            "--with-secrets",
            str(args.secrets),
            "--kubernetes-version",
            args.kubernetes_version,
            "--config-patch",
            f"@{common_patch}",
            "--config-patch-control-plane",
            f"@{node_patch}",
            "--output-types",
            "controlplane",
            "--output",
            str(output_path),
            "--force",
        ]
        subprocess.run(command, check=True)
        print(f"generated {output_path}")


if __name__ == "__main__":
    main()
