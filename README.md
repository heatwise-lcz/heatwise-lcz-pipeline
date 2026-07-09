# heatwise-lcz-pipeline

Chains the three HEATWISE EOAP processors into a single CWL `Workflow`,
end to end:

```
heatwise-hsi-lst-prep  ->  heatwise-patch-extraction  ->  heatwise-lcz-classification (train)  ->  heatwise-lcz-classification (predict)
```

This folder is **new and separate** from the three processor repos
(`../heatwise-hsi-lst-prep`, `../heatwise-patch-extraction`,
`../heatwise-lcz-classification`), which are **not modified** by anything
here. It only *references* their already-built Docker images and existing
`.cwl` files (for `prep` and `train`; see below for why `extract_patches`
and `predict` need a bit more).

## Why a merged glue+run step is needed (not a plain glue step)

Each processor takes a `config.yaml` whose *contents* reference file paths
(`inputs.hsi`, `inputs.sentinel2`, `weights`, ...). Plain CWL step-to-step
connections (`out: [x]` -> `in: y: step/x`) pass **files/directories**, not
the ability to rewrite the *content* of a YAML file to point at wherever an
upstream step's outputs got staged.

The first design here tried a separate "render the config" step followed by
a separate "run the processor with that config" step. **That failed in an
actual `cwltool` run**: each CWL step runs in its own container with its own
temporary file staging, so a path baked into the generated config by one
step's container (e.g. wherever `labels_dir` happened to be mounted) is not
valid in the *next* step's container -- `heatwise-patch-extraction` errored
with `<staged labels path> does not exist`.

The fix: **render the config and run the processor in the same container**,
via `tools/extract_patches_pipeline.cwl` / `tools/predict_pipeline.cwl` +
`scripts/run_patch_extraction.py` / `scripts/run_predict.py`. Each of these
does both steps back to back inside one `docker run`, so every staged path
stays valid the whole time.

Running a *different* script inside `heatwise-patch-extraction`'s /
`heatwise-lcz-classification`'s own image isn't possible directly, though:
those images use `ENTRYPOINT ["python", "/app/processor.py"]`, and Docker
*appends* `docker run IMAGE <args>` to a fixed `ENTRYPOINT` rather than
replacing it (confirmed by an earlier `cwltool` run against those repos'
own CWL). So `docker/*.Dockerfile` here build two **thin derived images**
(`FROM heatwise-patch-extraction:latest` / `FROM heatwise-lcz-classification:latest`,
with `ENTRYPOINT` cleared and `CMD` set instead, so `docker run` arguments
*do* fully replace it) -- this only layers on top of the existing verified
images, it doesn't touch the original Dockerfiles/repos.

## Pipeline diagram

```
                    ┌─────────────────────────┐
 prep_config ──────►│ prep                    │
 prep_catalog ─────►│ (heatwise-hsi-lst-prep) │──► output_directory ─┐
                    └─────────────────────────┘                     │
                                                                     ▼
 patch_config_template ─────►┌──────────────────────────────┐
 labels_dir/basename ───────►│ extract_patches               │
 sentinel2 ──────────────────►│ (render config + run          │──► patch_h5 ──┐
                              │  heatwise-patch-extraction,   │               │
                              │  merged, one container)       │               │
                              └──────────────────────────────┘               ▼
                                                              ┌──────────────────────────┐
                                               train_config ─►│ train                    │
                                                              │ (heatwise-lcz-           │──► output_directory ──┐
                                                              │  classification)         │                       │
                                                              └──────────────────────────┘                       │
                                                                                                                  ▼
 predict_config_template ───►┌──────────────────────────────┐
 experiment_name ────────────►│ predict                       │
 sentinel2 ───────────────────►│ (render config + run          │──► lcz_map
                              │  heatwise-lcz-classification, │
                              │  merged, one container)       │
                              └──────────────────────────────┘
```

## Build

The three original images must already be built (`heatwise-hsi-lst-prep:latest`,
`heatwise-patch-extraction:latest`, `heatwise-lcz-classification:latest`),
plus the two thin derived ones this repo adds:

```bash
docker build -f docker/patch-extraction-pipeline.Dockerfile -t heatwise-patch-extraction-pipeline:latest .
docker build -f docker/lcz-classification-pipeline.Dockerfile -t heatwise-lcz-classification-pipeline:latest .
```

## Run

```bash
cwltool heatwise_pipeline.cwl examples/job.yaml
```

`examples/job.yaml` reuses the already-verified sample data/configs that
ship in the three original repos (no data duplicated here -- only the two
templates, the two glue+run scripts, and the job file itself are new):

| Workflow input | Points at |
|---|---|
| `prep_config` | `../heatwise-hsi-lst-prep/examples/run_all_config_docker.yaml` |
| `prep_catalog` | `../heatwise-hsi-lst-prep/examples/stac_input/catalog_docker.json` |
| `sentinel2` | `../heatwise-hsi-lst-prep/examples/stac_input/Berlin_S2_2024-10-24_sample.tif` |
| `labels_dir` / `labels_basename` | `../heatwise-patch-extraction/data/Berlin` / `Berlin_labels_sample` |
| `train_config` | `../heatwise-lcz-classification/examples/train_config_sample.yaml` |
| `patch_config_template` / `predict_config_template` | `examples/*.yaml` (new, in this repo) |
| `extract_patches_script` / `predict_script` | `scripts/run_patch_extraction.py` / `scripts/run_predict.py` (new, in this repo) |

## Run locally without Docker/CWL

This is how the full chain was verified end to end (see Status below) and is
the "local Python test" level of the EOAP guideline. Only `pyyaml` is needed
(`pip install -r requirements.txt`); the three processor repos must sit next
to this folder and have their own environments installed. Run from this
folder:

```bash
# 1. prep -- writes 03_hsi_final/, 04_lst_final/ etc. under output/prep
python ../heatwise-hsi-lst-prep/processor.py run-all \
    --config ../heatwise-hsi-lst-prep/examples/run_all_config.yaml \
    --input-catalog ../heatwise-hsi-lst-prep/examples/stac_input/catalog.json \
    --output-dir output/prep

# 2. render patch config + extract patches (one script, same as in-container)
python scripts/run_patch_extraction.py \
    --template examples/patch_config_template.yaml \
    --prep-dir output/prep \
    --sentinel2 ../heatwise-hsi-lst-prep/examples/stac_input/Berlin_S2_2024-10-24_sample.tif \
    --labels-dir ../heatwise-patch-extraction/data/Berlin \
    --labels-basename Berlin_labels_sample \
    --output-h5 output/patches.h5 \
    --rendered-config output/patch_config_rendered.yaml \
    --processor ../heatwise-patch-extraction/processor.py

# 3. train
python ../heatwise-lcz-classification/processor.py train \
    --h5-dir output/patches.h5 \
    --config ../heatwise-lcz-classification/examples/train_config_sample.yaml \
    --output-dir output/train

# 4. render predict config + predict -> output/lcz_map.tif
python scripts/run_predict.py \
    --template examples/predict_config_template.yaml \
    --prep-dir output/prep \
    --sentinel2 ../heatwise-hsi-lst-prep/examples/stac_input/Berlin_S2_2024-10-24_sample.tif \
    --train-dir output/train \
    --experiment-name HSI-BS \
    --output output/lcz_map.tif \
    --rendered-config output/predict_config_rendered.yaml \
    --processor ../heatwise-lcz-classification/processor.py
```

The two glue scripts default `--processor` to `/app/processor.py` and
`--rendered-config` to `/tmp/...` (their in-container values); outside Docker
both must be overridden as above (on Windows `/tmp` doesn't exist at all).

## Status

- **The full chain's *logic* has been verified end to end locally in plain
  Python** (no Docker/CWL): ran `heatwise-hsi-lst-prep` ->
  `run_patch_extraction.py` (render + `heatwise-patch-extraction`) ->
  `train` -> `run_predict.py` (render + predict), using real intermediate
  outputs at each step, and it produced a valid LCZ map.
- **The full 4-step `Workflow` has passed an end-to-end `cwltool` run**
  (2026-07-09): `cwltool --outdir cwl_output heatwise_pipeline.cwl
  examples/job.yaml` finished with `Final process status is success`, all
  four steps (`prep` -> `extract_patches` -> `train` -> `predict`)
  completed, and `cwl_output/` contained the LCZ map GeoTIFF, patches.h5,
  and the prep/train directories. (The original two-step glue design --
  separate render/run steps -- had failed as described above and was
  redesigned into the current merged single-step-per-stage architecture
  before this run.)
- **Windows note**: recent cwltool versions dropped native-Windows support
  and crash on Unix-only APIs (`import pwd` in cwltool's cwlprov and in
  spython, `os.geteuid()` in cwltool's docker.py). The run above needed
  three small guards patched into site-packages; a `pip install --upgrade`
  of cwltool/spython will undo them. The officially supported route is
  running cwltool inside WSL2.
- **Known wart**: `prep_output` and `train_output` are both directories
  literally named `output`, so with a shared `--outdir` their contents get
  merged into one `output/` folder (prep's 01..04 subfolders + train's
  best_model/confusion-matrix files side by side). Harmless, but rename one
  of the steps' `output_dir` inputs if clean separation is wanted.
