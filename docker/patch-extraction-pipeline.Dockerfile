# Thin derived image (heatwise-lcz-pipeline only, does NOT modify
# heatwise-patch-extraction). Two changes on top of the base image:
#
# 1. The render+run glue script is baked in at /app/run_patch_extraction.py,
#    so the CWL tool can call it directly instead of passing the script
#    around as a CWL File input (code should live in the image, not travel
#    as workflow data).
# 2. The upstream heatwise-patch-extraction image uses ENTRYPOINT ["python",
#    "/app/processor.py"]; Docker always *appends* `docker run IMAGE <args>`
#    to a fixed ENTRYPOINT rather than replacing it, so it's not possible to
#    run a *different* script inside that image via CWL's normal command
#    construction. Clearing ENTRYPOINT and using CMD instead (which
#    `docker run` *does* fully replace) restores that ability, without
#    touching the original repo/image at all.
#
# Build from the repo root:
# docker build -f docker/patch-extraction-pipeline.Dockerfile -t ghcr.io/heatwise-lcz/heatwise-patch-extraction-pipeline:0.1.0 .
#
# Before the base image is published, build/tag it locally with this same
# release-shaped name:
# docker build -t ghcr.io/heatwise-lcz/heatwise-patch-extraction:0.1.0 ../heatwise-patch-extraction
FROM ghcr.io/heatwise-lcz/heatwise-patch-extraction:0.1.0
COPY scripts/run_patch_extraction.py /app/run_patch_extraction.py
ENTRYPOINT []
CMD ["python", "/app/run_patch_extraction.py", "--help"]
