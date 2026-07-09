#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
Glue script (heatwise-lcz-pipeline only, not part of heatwise-patch-extraction).

Renders a heatwise-patch-extraction config.yaml from CWL-staged inputs, then
immediately invokes /app/processor.py *in the same process/container*.

This must NOT be split into "render config in step N" + "run processor in
step N+1": each CWL step runs in its own container with its own temporary
mounts, so a path baked into a file in one step's container (e.g. where
`labels_dir` happened to be staged) is not valid in a different step's
container. Rendering the config and consuming it have to happen in the same
container invocation -- confirmed by an actual cwltool run that failed with
"<staged labels path> does not exist" once the config-writing and
config-reading steps were split into two separate CWL steps.
"""
from __future__ import annotations

import argparse
import glob
import os
import subprocess
import sys

import yaml


def find_one(pattern: str, label: str) -> str:
    matches = sorted(glob.glob(pattern))
    if not matches:
        raise SystemExit(f"[run_patch_extraction] No file found for {label} (pattern: {pattern})")
    if len(matches) > 1:
        print(f"[run_patch_extraction] Warning: multiple matches for {label}, using the first: {matches}")
    return matches[0]


def main():
    parser = argparse.ArgumentParser(description="Render config + run heatwise-patch-extraction, in one container")
    parser.add_argument("--template", required=True, help="Base config.yaml with everything except file paths")
    parser.add_argument("--prep-dir", required=True, help="heatwise-hsi-lst-prep output directory")
    parser.add_argument("--sentinel2", required=True, help="Path to the Sentinel-2 raster (not produced by prep)")
    parser.add_argument("--labels-dir", required=True,
                         help="Directory containing the labels .shp and its .shx/.dbf/.prj/.cpg siblings")
    parser.add_argument("--labels-basename", required=True, help='e.g. "Berlin_labels_sample" (no .shp extension)')
    parser.add_argument("--output-h5", required=True, help="Output H5 path, passed through to processor.py")
    parser.add_argument("--rendered-config", default="/tmp/patch_config_rendered.yaml",
                         help="Where to write the intermediate rendered config (container-local scratch path)")
    parser.add_argument("--processor", default="/app/processor.py")
    args = parser.parse_args()

    with open(args.template, "r", encoding="utf-8") as f:
        cfg = yaml.safe_load(f)

    hsi_path = find_one(os.path.join(args.prep_dir, "03_hsi_final", "hsi_bs", "*.tif"), "hsi_bs")
    lst_matches = sorted(glob.glob(os.path.join(args.prep_dir, "04_lst_final", "*.tif")))
    lst_path = lst_matches[0] if lst_matches else None

    cfg.setdefault("inputs", {})
    cfg["inputs"]["hsi"] = hsi_path
    cfg["inputs"]["sentinel2"] = args.sentinel2
    if lst_path:
        cfg["inputs"]["lst"] = lst_path
        cfg.setdefault("toggles", {})["use_lst"] = True
    else:
        print("[run_patch_extraction] No LST output found under 04_lst_final/; leaving toggles.use_lst as in the template")

    labels_shp = os.path.join(args.labels_dir, f"{args.labels_basename}.shp")
    if not os.path.exists(labels_shp):
        raise SystemExit(f"[run_patch_extraction] Labels shapefile not found: {labels_shp}")
    cfg.setdefault("labels", {})["shp"] = labels_shp

    os.makedirs(os.path.dirname(args.rendered_config) or ".", exist_ok=True)
    with open(args.rendered_config, "w", encoding="utf-8") as f:
        yaml.safe_dump(cfg, f, sort_keys=False)

    print(f"[run_patch_extraction] hsi={hsi_path}")
    print(f"[run_patch_extraction] sentinel2={args.sentinel2}")
    print(f"[run_patch_extraction] lst={lst_path}")
    print(f"[run_patch_extraction] labels.shp={labels_shp}")
    print(f"[run_patch_extraction] Rendered config -> {args.rendered_config}")

    cmd = ["python", args.processor, "--config", args.rendered_config, "--output-h5", args.output_h5]
    print(f"[run_patch_extraction] Running: {' '.join(cmd)}")
    sys.exit(subprocess.call(cmd))


if __name__ == "__main__":
    main()
