cwlVersion: v1.2
class: CommandLineTool

label: Render config + run heatwise-patch-extraction (merged, one container)
doc: >
  Glue step (heatwise-lcz-pipeline only). Renders a heatwise-patch-extraction
  config.yaml from heatwise-hsi-lst-prep's output directory + a labels
  Directory + the original Sentinel-2 raster, then immediately invokes
  heatwise-patch-extraction's own /app/processor.py *inside the same
  container* (scripts/run_patch_extraction.py does both, back to back).

  This is deliberately ONE CWL step, not two ("render config" then "run
  processor" as separate steps): each CWL step runs in its own container
  with its own temporary file staging, so a path baked into a file by one
  step's container is not valid in a different step's container -- confirmed
  by an actual cwltool run that failed with "<staged labels path> does not
  exist" once config-rendering and config-consumption were split across two
  steps.

  Uses a thin derived image (docker/patch-extraction-pipeline.Dockerfile,
  `FROM heatwise-patch-extraction:latest` with ENTRYPOINT cleared) instead of
  the original image directly: the original's `ENTRYPOINT ["python",
  "/app/processor.py"]` can only be *appended to* by `docker run` arguments,
  never replaced, which would make it impossible to run this different
  script (scripts/run_patch_extraction.py) at all.

requirements:
  DockerRequirement:
    dockerImageId: heatwise-patch-extraction-pipeline:latest
    dockerPull: ghcr.io/heatwise/heatwise-patch-extraction-pipeline:latest

baseCommand: python

inputs:
  script:
    type: File
    inputBinding: {position: 1}
    doc: scripts/run_patch_extraction.py

  template:
    type: File
    inputBinding: {prefix: --template, position: 2}

  prep_dir:
    type: Directory
    inputBinding: {prefix: --prep-dir, position: 3}

  sentinel2:
    type: File
    inputBinding: {prefix: --sentinel2, position: 4}

  labels_dir:
    type: Directory
    inputBinding: {prefix: --labels-dir, position: 5}

  labels_basename:
    type: string
    inputBinding: {prefix: --labels-basename, position: 6}

  output_h5_name:
    type: string
    default: output/patches.h5
    inputBinding: {prefix: --output-h5, position: 7}
    doc: Nested under output/ for consistency with prep/train's own output_dir convention.

outputs:
  patch_h5:
    type: File
    outputBinding:
      glob: $(inputs.output_h5_name)
