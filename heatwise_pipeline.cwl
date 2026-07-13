cwlVersion: v1.2
class: Workflow

label: HEATWISE LCZ full pipeline
doc: >
  Chains all three HEATWISE EOAP processors end to end:
  heatwise-hsi-lst-prep -> heatwise-patch-extraction ->
  heatwise-lcz-classification (train) -> heatwise-lcz-classification
  (predict). This repository is a self-contained EOAP workflow package: the
  prep and train steps run vendored copies of the upstream processors' own
  CWL files (tools/hsi_lst_prep.cwl, tools/lcz_train.cwl -- the processors'
  code itself lives in their Docker images, referenced via
  DockerRequirement), and the patch-extraction and predict stages are
  wrapped by two merged glue+run CommandLineTools
  (tools/extract_patches_pipeline.cwl, tools/predict_pipeline.cwl) whose
  glue scripts are baked into thin derived images. The merged tools exist
  because those processors take a single config.yaml whose *content*
  references file paths, and a plain CWL step connection can't rewrite that
  content to point at wherever an upstream step's outputs got staged: the
  config must be rendered *and* consumed inside the same container
  invocation (this was originally two separate steps/tools and failed with
  a "file does not exist" error in an actual cwltool run once the two
  containers' independent file staging came into play). The final step also
  writes a STAC catalog + item describing the pipeline's end products.

inputs:
  prep_config:
    type: File
    doc: heatwise-hsi-lst-prep run-all config (examples/run_all_config_docker.yaml; paths inside it are /app/... paths into the prep image)
  prep_catalog:
    type: File
    doc: heatwise-hsi-lst-prep STAC input catalog (examples/prep_catalog_docker.json; item/asset hrefs are /app/... paths into the prep image)
  sentinel2:
    type: File
    doc: Raw Sentinel-2 raster (same scene referenced inside prep_catalog's item; also needed directly by patch-extraction and predict). Sample under data/.
  patch_config_template:
    type: File
    doc: heatwise-patch-extraction config template, missing inputs.*/labels.shp (examples/patch_config_template.yaml)
  labels_dir:
    type: Directory
    doc: Directory containing the labels .shp + siblings (sample under data/Berlin_labels)
  labels_basename:
    type: string
    doc: e.g. "Berlin_labels" (no .shp extension)
  train_config:
    type: File
    doc: heatwise-lcz-classification train config (examples/train_config_sample.yaml)
  predict_config_template:
    type: File
    doc: heatwise-lcz-classification predict config template, missing inputs.*/weights (examples/predict_config_template.yaml)
  experiment_name:
    type: string
    default: HSI-BS
    doc: Must match one entry in train_config's experiments[].name

steps:
  prep:
    run: tools/hsi_lst_prep.cwl
    in:
      config: prep_config
      input_catalog: prep_catalog
      output_dir: {default: prep_output}
    out: [output_directory]

  extract_patches:
    run: tools/extract_patches_pipeline.cwl
    in:
      template: patch_config_template
      prep_dir: prep/output_directory
      sentinel2: sentinel2
      labels_dir: labels_dir
      labels_basename: labels_basename
    out: [patch_h5]

  train:
    run: tools/lcz_train.cwl
    in:
      h5_dir: extract_patches/patch_h5
      config: train_config
      output_dir: {default: train_output}
    out: [output_directory]

  predict:
    run: tools/predict_pipeline.cwl
    in:
      template: predict_config_template
      prep_dir: prep/output_directory
      sentinel2: sentinel2
      train_dir: train/output_directory
      experiment_name: experiment_name
    out: [lcz_map, lcz_map_preview, stac_catalog, output_directory]

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
  lcz_map_preview:
    type: File?
    outputSource: predict/lcz_map_preview
    doc: Colour preview PNG of the final LCZ map.
  stac_catalog:
    type: File
    outputSource: predict/stac_catalog
    doc: Root STAC catalog for the final pipeline products (LCZ map + training metrics).
  predict_output:
    type: Directory
    outputSource: predict/output_directory
