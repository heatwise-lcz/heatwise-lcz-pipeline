#!/usr/bin/env bash
# Local (no Docker/CWL) smoke test of the full HEATWISE LCZ pipeline --
# the "local Python test" level of the EOAP guideline.
#
# Prerequisites:
#   - the three processor repos checked out with their environments installed
#     (override their locations via PREP_REPO / PATCH_REPO / LCZ_REPO);
#   - pyyaml for the glue scripts (pip install -r requirements.txt).
#
# Usage (from the repo root):
#   bash examples/run_local.sh
#
# Everything is written under output/ (gitignored). For the CWL-level test
# run instead:
#   cwltool --outdir cwl_output heatwise_pipeline.cwl examples/job.yaml
set -euo pipefail

cd "$(dirname "$0")/.."

PREP_REPO="${PREP_REPO:-../heatwise-hsi-lst-prep}"
PATCH_REPO="${PATCH_REPO:-../heatwise-patch-extraction}"
LCZ_REPO="${LCZ_REPO:-../heatwise-lcz-classification}"
EXPERIMENT="${EXPERIMENT:-HSI-BS}"
OUT="${OUT:-output}"

for repo in "$PREP_REPO" "$PATCH_REPO" "$LCZ_REPO"; do
    if [ ! -f "$repo/processor.py" ]; then
        echo "ERROR: processor repo not found at '$repo' (set PREP_REPO/PATCH_REPO/LCZ_REPO)" >&2
        exit 1
    fi
done

echo "== 1/4 prep (heatwise-hsi-lst-prep run-all) =="
python "$PREP_REPO/processor.py" run-all \
    --config "$PREP_REPO/examples/run_all_config.yaml" \
    --input-catalog "$PREP_REPO/examples/stac_input/catalog.json" \
    --output-dir "$OUT/prep"

echo "== 2/4 extract_patches (render config + run) =="
python scripts/run_patch_extraction.py \
    --template examples/patch_config_template.yaml \
    --prep-dir "$OUT/prep" \
    --sentinel2 data/Berlin_S2_2024-10-24_sample.tif \
    --labels-dir data/Berlin_labels \
    --labels-basename Berlin_labels_sample \
    --output-h5 "$OUT/patches.h5" \
    --rendered-config "$OUT/patch_config_rendered.yaml" \
    --processor "$PATCH_REPO/processor.py"

echo "== 3/4 train =="
python "$LCZ_REPO/processor.py" train \
    --h5-dir "$OUT/patches.h5" \
    --config examples/train_config_sample.yaml \
    --output-dir "$OUT/train"

echo "== 4/4 predict (render config + predict + STAC) =="
python scripts/run_predict.py \
    --template examples/predict_config_template.yaml \
    --prep-dir "$OUT/prep" \
    --sentinel2 data/Berlin_S2_2024-10-24_sample.tif \
    --train-dir "$OUT/train" \
    --experiment-name "$EXPERIMENT" \
    --output-dir "$OUT/predict" \
    --rendered-config "$OUT/predict_config_rendered.yaml" \
    --processor "$LCZ_REPO/processor.py"

echo
echo "Done. Final products in $OUT/predict:"
ls "$OUT/predict"
