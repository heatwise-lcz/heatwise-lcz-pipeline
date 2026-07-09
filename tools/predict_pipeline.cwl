cwlVersion: v1.2
class: CommandLineTool

label: Render config + run heatwise-lcz-classification predict (merged, one container)
doc: >
  Glue step (heatwise-lcz-pipeline only). Renders a heatwise-lcz-classification
  predict config.yaml from heatwise-hsi-lst-prep's output directory +
  heatwise-lcz-classification's train output directory + the original
  Sentinel-2 raster, then immediately invokes `/app/processor.py predict`
  *inside the same container* (scripts/run_predict.py does both, back to
  back) -- see tools/extract_patches_pipeline.cwl's doc for why this must be
  one step rather than two, and why a thin derived image
  (docker/lcz-classification-pipeline.Dockerfile) is used instead of the
  original image directly.

requirements:
  DockerRequirement:
    dockerImageId: heatwise-lcz-classification-pipeline:latest
    dockerPull: ghcr.io/heatwise/heatwise-lcz-classification-pipeline:latest

baseCommand: python

inputs:
  script:
    type: File
    inputBinding: {position: 1}
    doc: scripts/run_predict.py

  template:
    type: File
    inputBinding: {prefix: --template, position: 2}

  prep_dir:
    type: Directory
    inputBinding: {prefix: --prep-dir, position: 3}

  sentinel2:
    type: File
    inputBinding: {prefix: --sentinel2, position: 4}

  train_dir:
    type: Directory
    inputBinding: {prefix: --train-dir, position: 5}

  experiment_name:
    type: string
    inputBinding: {prefix: --experiment-name, position: 6}
    doc: Must match one of train_config's experiments[].name (e.g. "HSI-BS").

  output_name:
    type: string
    default: output/lcz_map.tif
    inputBinding: {prefix: --output, position: 7}
    doc: Nested under output/ for consistency with prep/train's own output_dir convention.

outputs:
  lcz_map:
    type: File
    outputBinding:
      glob: $(inputs.output_name)
