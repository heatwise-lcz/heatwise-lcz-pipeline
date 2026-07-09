# Thin derived image (heatwise-lcz-pipeline only, does NOT modify
# heatwise-lcz-classification) -- see patch-extraction-pipeline.Dockerfile's
# comment for why this is needed (ENTRYPOINT vs CMD command-replacement
# semantics).
FROM heatwise-lcz-classification:latest
ENTRYPOINT []
CMD ["python", "/app/processor.py"]
