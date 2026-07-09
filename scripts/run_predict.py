#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
Glue script (heatwise-lcz-pipeline only, not part of heatwise-lcz-classification).

Renders a heatwise-lcz-classification predict config.yaml from CWL-staged
inputs, then immediately invokes /app/processor.py *in the same
process/container* -- see run_patch_extraction.py's docstring for why this
can't be split across two CWL steps.
"""
from __future__ import annotations

import argparse
import glob
import os
import re
import subprocess
import sys

import yaml


def clean_name(value: str) -> str:
    """Must match heatwise-lcz-classification/src/heatwise_lcz_classification/train.py's clean_name()."""
    return re.sub(r"[^A-Za-z0-9_.-]+", "_", value)


def find_one(pattern: str, label: str) -> str:
    matches = sorted(glob.glob(pattern))
    if not matches:
        raise SystemExit(f"[run_predict] No file found for {label} (pattern: {pattern})")
    if len(matches) > 1:
        print(f"[run_predict] Warning: multiple matches for {label}, using the first: {matches}")
    return matches[0]


def main():
    parser = argparse.ArgumentParser(description="Render config + run heatwise-lcz-classification predict, in one container")
    parser.add_argument("--template", required=True, help="Base config.yaml with everything except file paths")
    parser.add_argument("--prep-dir", required=True, help="heatwise-hsi-lst-prep output directory")
    parser.add_argument("--sentinel2", required=True, help="Path to the Sentinel-2 raster")
    parser.add_argument("--train-dir", required=True, help="heatwise-lcz-classification train output directory")
    parser.add_argument("--experiment-name", required=True, help="Must match one of train_config's experiments[].name")
    parser.add_argument("--output", required=True, help="Output LCZ map path, passed through to processor.py")
    parser.add_argument("--rendered-config", default="/tmp/predict_config_rendered.yaml",
                         help="Where to write the intermediate rendered config (container-local scratch path)")
    parser.add_argument("--processor", default="/app/processor.py")
    args = parser.parse_args()

    with open(args.template, "r", encoding="utf-8") as f:
        cfg = yaml.safe_load(f)

    hsi_path = find_one(os.path.join(args.prep_dir, "03_hsi_final", "hsi_bs", "*.tif"), "hsi_bs")
    weights_path = os.path.join(args.train_dir, f"best_model_{clean_name(args.experiment_name)}.pth")
    if not os.path.exists(weights_path):
        raise SystemExit(f"[run_predict] No checkpoint found at {weights_path}")

    cfg.setdefault("inputs", {})
    cfg["inputs"]["hsi"] = hsi_path
    cfg["inputs"]["sen2"] = args.sentinel2
    cfg["weights"] = weights_path

    os.makedirs(os.path.dirname(args.rendered_config) or ".", exist_ok=True)
    with open(args.rendered_config, "w", encoding="utf-8") as f:
        yaml.safe_dump(cfg, f, sort_keys=False)

    print(f"[run_predict] hsi={hsi_path}")
    print(f"[run_predict] sen2={args.sentinel2}")
    print(f"[run_predict] weights={weights_path}")
    print(f"[run_predict] Rendered config -> {args.rendered_config}")

    cmd = ["python", args.processor, "predict", "--config", args.rendered_config, "--output", args.output]
    print(f"[run_predict] Running: {' '.join(cmd)}")
    sys.exit(subprocess.call(cmd))


if __name__ == "__main__":
    main()
