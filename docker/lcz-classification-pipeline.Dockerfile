# Thin derived image (heatwise-lcz-pipeline only, does NOT modify
# heatwise-lcz-classification) -- see patch-extraction-pipeline.Dockerfile's
# comment for why the glue script is baked in and why ENTRYPOINT is cleared
# (ENTRYPOINT vs CMD command-replacement semantics).
#
# Build from the repo root:
# docker build -f docker/lcz-classification-pipeline.Dockerfile -t ghcr.io/heatwise-lcz/heatwise-lcz-classification-pipeline:0.1.0 .
#
# Before the base image is published, build/tag it locally with this same
# release-shaped name:
# docker build -t ghcr.io/heatwise-lcz/heatwise-lcz-classification:0.1.0 ../heatwise-lcz-classification
FROM ghcr.io/heatwise-lcz/heatwise-lcz-classification:0.1.0
COPY scripts/run_predict.py /app/run_predict.py
ENTRYPOINT []
CMD ["python", "/app/run_predict.py", "--help"]
