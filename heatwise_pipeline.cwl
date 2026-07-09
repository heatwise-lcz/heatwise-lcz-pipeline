cwlVersion: v1.2
class: Workflow

label: HEATWISE LCZ full pipeline
doc: >
  Chains all three HEATWISE EOAP processors end to end:
  heatwise-hsi-lst-prep -> heatwise-patch-extraction ->
  heatwise-lcz-classification (train) -> heatwise-lcz-classification
  (predict). Each processor's own .cwl file (in the original, untouched
  repos) is reused as-is via `run:` for `prep` and `train`. The
  patch-extraction and predict stages are wrapped by two merged glue+run
  CommandLineTools (tools/extract_patches_pipeline.cwl,
  tools/predict_pipeline.cwl) instead of calling their repos' own .cwl
  files directly: those tools take a single `config.yaml` whose *content*
  references file paths, and a plain CWL step connection can't rewrite that
  content to point at wherever an upstream step's outputs got staged. The
  merged tools render the config *and* run the processor in the same
  container invocation, in one CWL step, so the staged paths stay valid
  throughout -- see tools/extract_patches_pipeline.cwl's doc for the full
  explanation (this was originally two separate steps/tools and failed with
  a "file does not exist" error in an actual cwltool run once the two
  containers' independent file staging came into play).

inputs:
  prep_config:
    type: File
    doc: heatwise-hsi-lst-prep run-all config (see that repo's examples/run_all_config_docker.yaml)
  prep_catalog:
    type: File
    doc: heatwise-hsi-lst-prep STAC input catalog (see examples/stac_input/catalog_docker.json)
  sentinel2:
    type: File
    doc: Raw Sentinel-2 raster (same one referenced inside prep_catalog's item; also needed directly by patch-extraction and predict)
  patch_config_template:
    type: File
    doc: heatwise-patch-extraction config template, missing inputs.*/labels.shp (see examples/patch_config_template.yaml)
  labels_dir:
    type: Directory
    doc: Directory containing the labels .shp + siblings (e.g. heatwise-patch-extraction/data/Berlin)
  labels_basename:
    type: string
    doc: e.g. "Berlin_labels_sample" (no .shp extension)
  train_config:
    type: File
    doc: heatwise-lcz-classification train config (see examples/train_config_sample.yaml)
  predict_config_template:
    type: File
    doc: heatwise-lcz-classification predict config template, missing inputs.*/weights (see examples/predict_config_template.yaml)
  experiment_name:
    type: string
    default: HSI-BS
    doc: Must match one entry in train_config's experiments[].name
  extract_patches_script:
    type: File
    doc: scripts/run_patch_extraction.py
  predict_script:
    type: File
    doc: scripts/run_predict.py

steps:
  prep:
    run: ../heatwise-hsi-lst-prep/heatwise_hsi_lst_prep.cwl
    in:
      config: prep_config
      input_catalog: prep_catalog
    out: [output_directory]

  extract_patches:
    run: tools/extract_patches_pipeline.cwl
    in:
      script: extract_patches_script
      template: patch_config_template
      prep_dir: prep/output_directory
      sentinel2: sentinel2
      labels_dir: labels_dir
      labels_basename: labels_basename
    out: [patch_h5]

  train:
    run: ../heatwise-lcz-classification/heatwise_lcz_train.cwl
    in:
      h5_dir: extract_patches/patch_h5
      config: train_config
    out: [output_directory]

  predict:
    run: tools/predict_pipeline.cwl
    in:
      script: predict_script
      template: predict_config_template
      prep_dir: prep/output_directory
      sentinel2: sentinel2
      train_dir: train/output_directory
      experiment_name: experiment_name
    out: [lcz_map]

outputs:
  prep_output:
    type: Directory
    outputSource: prep/output_directory
  patch_h5:
    type: File
    outputSource: extract_patches/patch_h5
  train_output:
    type: Directory
    outputSource: train/output_directory
  lcz_map:
    type: File
    outputSource: predict/lcz_map
