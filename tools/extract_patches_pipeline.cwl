cwlVersion: v1.2
class: CommandLineTool

label: Render config + run heatwise-patch-extraction (merged, one container)
doc: >
  Glue step (heatwise-lcz-pipeline only). Renders a heatwise-patch-extraction
  config.yaml from heatwise-hsi-lst-prep's output directory + a labels
  Directory + the original Sentinel-2 raster, then immediately invokes
  heatwise-patch-extraction's own /app/processor.py *inside the same
  container* (/app/run_patch_extraction.py, baked into the derived image by
  docker/patch-extraction-pipeline.Dockerfile, does both back to back).

  This is deliberately ONE CWL step, not two ("render config" then "run
  processor" as separate steps): each CWL step runs in its own container
  with its own temporary file staging, so a path baked into a file by one
  step's container is not valid in a different step's container -- confirmed
  by an actual cwltool run that failed with "<staged labels path> does not
  exist" once config-rendering and config-consumption were split across two
  steps.

  Uses a thin derived image (docker/patch-extraction-pipeline.Dockerfile,
  built from the versioned heatwise-patch-extraction base image with the glue
  script COPYed in and ENTRYPOINT cleared) instead of the original image
  directly: the original's
  `ENTRYPOINT ["python", "/app/processor.py"]` can only be *appended to* by
  `docker run` arguments, never replaced, which would make it impossible to
  run this different script at all.

requirements:
  DockerRequirement:
    dockerImageId: ghcr.io/heatwise-lcz/heatwise-patch-extraction-pipeline:0.1.1
    dockerPull: ghcr.io/heatwise-lcz/heatwise-patch-extraction-pipeline:0.1.1

baseCommand: python
arguments:
  # Absolute path: cwltool overrides the container working directory with a
  # per-job staging directory, so the script must be addressed inside the
  # image, not relative to the workdir.
  - /app/run_patch_extraction.py

inputs:
  template:
    type: File
    inputBinding: {prefix: --template}

  prep_dir:
    type: Directory
    inputBinding: {prefix: --prep-dir}

  sentinel2:
    type: File
    inputBinding: {prefix: --sentinel2}

  labels_dir:
    type: Directory
    inputBinding: {prefix: --labels-dir}

  labels_basename:
    type: string
    inputBinding: {prefix: --labels-basename}

  output_h5_name:
    type: string
    default: output/patches.h5
    inputBinding: {prefix: --output-h5}
    doc: Nested under output/ for consistency with the other steps' output_dir convention.

outputs:
  patch_h5:
    type: File
    outputBinding:
      glob: $(inputs.output_h5_name)
