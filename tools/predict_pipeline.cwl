cwlVersion: v1.2
class: CommandLineTool

label: Render config + run heatwise-lcz-classification predict + write STAC (merged, one container)
doc: >
  Glue step (heatwise-lcz-pipeline only). Renders a heatwise-lcz-classification
  predict config.yaml from heatwise-hsi-lst-prep's output directory +
  heatwise-lcz-classification's train output directory + the original
  Sentinel-2 raster, invokes `/app/processor.py predict` *inside the same
  container* (/app/run_predict.py, baked into the derived image by
  docker/lcz-classification-pipeline.Dockerfile, does both back to back --
  see tools/extract_patches_pipeline.cwl's doc for why this must be one step
  rather than two, and why a thin derived image is used instead of the
  original image directly), then writes a STAC catalog + item describing the
  final pipeline products (LCZ map + training metrics copied from the train
  output).

requirements:
  DockerRequirement:
    dockerImageId: ghcr.io/heatwise-lcz/heatwise-lcz-classification-pipeline:0.1.1
    dockerPull: ghcr.io/heatwise-lcz/heatwise-lcz-classification-pipeline:0.1.1

baseCommand: python
arguments:
  - /app/run_predict.py

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

  train_dir:
    type: Directory
    inputBinding: {prefix: --train-dir}

  experiment_name:
    type: string
    inputBinding: {prefix: --experiment-name}
    doc: Must match one of train_config's experiments[].name (e.g. "HSI-BS").

  output_dir_name:
    type: string
    default: predict_output
    inputBinding: {prefix: --output-dir}
    doc: Directory receiving lcz_map.tif, metric CSV copies, and the STAC catalog/item.

outputs:
  lcz_map:
    type: File
    outputBinding:
      glob: $(inputs.output_dir_name)/lcz_map.tif

  stac_catalog:
    type: File
    outputBinding:
      glob: $(inputs.output_dir_name)/catalog.json
    doc: Root STAC catalog for the final pipeline products.

  output_directory:
    type: Directory
    outputBinding:
      glob: $(inputs.output_dir_name)
    doc: Full final-products directory (LCZ map, metric copies, STAC catalog + item).
