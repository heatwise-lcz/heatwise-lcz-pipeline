#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
Glue script (heatwise-lcz-pipeline only, not part of heatwise-lcz-classification).

Renders a heatwise-lcz-classification predict config.yaml from CWL-staged
inputs, invokes /app/processor.py predict *in the same process/container*
(see run_patch_extraction.py's docstring for why this can't be split across
two CWL steps), then writes a STAC item + catalog describing the final
pipeline products (LCZ map + training metrics copied from the train step).
"""
from __future__ import annotations

import argparse
import glob
import json
import os
import re
import shutil
import subprocess
import sys
from datetime import datetime, timezone

import yaml

LCZ_MAP_NAME = "lcz_map.tif"


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


def raster_bbox_wgs84(path: str):
    """Return (bbox, geometry) of a raster in EPSG:4326, or (None, None) if rasterio is unavailable."""
    try:
        import rasterio
        from rasterio.warp import transform_bounds

        with rasterio.open(path) as ds:
            w, s, e, n = transform_bounds(ds.crs, "EPSG:4326", *ds.bounds)
        bbox = [w, s, e, n]
        geometry = {
            "type": "Polygon",
            "coordinates": [[[w, s], [e, s], [e, n], [w, n], [w, s]]],
        }
        return bbox, geometry
    except Exception as exc:  # local runs may lack rasterio; STAC then has null extent
        print(f"[run_predict] Warning: could not derive bbox from {path}: {exc}")
        return None, None


def write_stac(output_dir: str, experiment_name: str, metric_files: list[str]) -> None:
    bbox, geometry = raster_bbox_wgs84(os.path.join(output_dir, LCZ_MAP_NAME))

    assets = {
        "lcz_map": {
            "href": LCZ_MAP_NAME,
            "type": "image/tiff; application=geotiff",
            "title": "Local Climate Zone classification map",
            "roles": ["data"],
        }
    }
    for path in metric_files:
        name = os.path.basename(path)
        assets[os.path.splitext(name)[0]] = {
            "href": name,
            "type": "text/csv",
            "title": f"Training metric: {name}",
            "roles": ["metadata"],
        }

    item = {
        "type": "Feature",
        "stac_version": "1.0.0",
        "id": f"heatwise-lcz-pipeline-{clean_name(experiment_name)}",
        "properties": {
            "datetime": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "processing:software": "heatwise-lcz-pipeline",
            "heatwise:experiment": experiment_name,
        },
        "geometry": geometry,
        "bbox": bbox,
        "links": [
            {"rel": "root", "href": "catalog.json", "type": "application/json"},
            {"rel": "parent", "href": "catalog.json", "type": "application/json"},
        ],
        "assets": assets,
    }
    item_path = os.path.join(output_dir, "lcz_product_item.json")
    with open(item_path, "w", encoding="utf-8") as f:
        json.dump(item, f, indent=2)

    catalog = {
        "type": "Catalog",
        "stac_version": "1.0.0",
        "id": "heatwise-lcz-pipeline-output",
        "description": "Final products of the HEATWISE LCZ end-to-end pipeline",
        "links": [
            {"rel": "root", "href": "catalog.json", "type": "application/json"},
            {"rel": "item", "href": "lcz_product_item.json", "type": "application/json"},
        ],
    }
    with open(os.path.join(output_dir, "catalog.json"), "w", encoding="utf-8") as f:
        json.dump(catalog, f, indent=2)
    print(f"[run_predict] STAC catalog + item written under {output_dir}")


def main():
    parser = argparse.ArgumentParser(
        description="Render config + run heatwise-lcz-classification predict + write STAC, in one container"
    )
    parser.add_argument("--template", required=True, help="Base config.yaml with everything except file paths")
    parser.add_argument("--prep-dir", required=True, help="heatwise-hsi-lst-prep output directory")
    parser.add_argument("--sentinel2", required=True, help="Path to the Sentinel-2 raster")
    parser.add_argument("--train-dir", required=True, help="heatwise-lcz-classification train output directory")
    parser.add_argument("--experiment-name", required=True, help="Must match one of train_config's experiments[].name")
    parser.add_argument("--output-dir", required=True,
                         help=f"Directory for the final products ({LCZ_MAP_NAME}, metrics copies, STAC catalog/item)")
    parser.add_argument("--rendered-config", default="/tmp/predict_config_rendered.yaml",
                         help="Where to write the intermediate rendered config (container-local scratch path)")
    parser.add_argument("--processor", default="/app/processor.py")
    args = parser.parse_args()

    with open(args.template, "r", encoding="utf-8") as f:
        cfg = yaml.safe_load(f)

    hsi_path = find_one(os.path.join(args.prep_dir, "03_hsi_final", "hsi_bs", "*.tif"), "hsi_bs")
    exp = clean_name(args.experiment_name)
    weights_path = os.path.join(args.train_dir, f"best_model_{exp}.pth")
    if not os.path.exists(weights_path):
        raise SystemExit(f"[run_predict] No checkpoint found at {weights_path}")

    cfg.setdefault("inputs", {})
    cfg["inputs"]["hsi"] = hsi_path
    cfg["inputs"]["sen2"] = args.sentinel2
    cfg["weights"] = weights_path

    os.makedirs(os.path.dirname(args.rendered_config) or ".", exist_ok=True)
    with open(args.rendered_config, "w", encoding="utf-8") as f:
        yaml.safe_dump(cfg, f, sort_keys=False)

    os.makedirs(args.output_dir, exist_ok=True)
    lcz_map_path = os.path.join(args.output_dir, LCZ_MAP_NAME)

    print(f"[run_predict] hsi={hsi_path}")
    print(f"[run_predict] sen2={args.sentinel2}")
    print(f"[run_predict] weights={weights_path}")
    print(f"[run_predict] Rendered config -> {args.rendered_config}")

    cmd = ["python", args.processor, "predict", "--config", args.rendered_config, "--output", lcz_map_path]
    print(f"[run_predict] Running: {' '.join(cmd)}")
    ret = subprocess.call(cmd)
    if ret != 0:
        sys.exit(ret)

    metric_files = []
    for pattern in (f"per_class_accuracy_{exp}.csv", f"confusion_matrix_{exp}.csv", "summary.csv"):
        for src in sorted(glob.glob(os.path.join(args.train_dir, pattern))):
            dst = os.path.join(args.output_dir, os.path.basename(src))
            shutil.copyfile(src, dst)
            metric_files.append(dst)
    write_stac(args.output_dir, args.experiment_name, metric_files)
    sys.exit(0)


if __name__ == "__main__":
    main()
