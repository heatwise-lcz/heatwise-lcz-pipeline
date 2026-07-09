# Thin derived image (heatwise-lcz-pipeline only, does NOT modify
# heatwise-patch-extraction). heatwise-patch-extraction:latest uses
# ENTRYPOINT ["python", "/app/processor.py"]; Docker always *appends*
# `docker run IMAGE <args>` to a fixed ENTRYPOINT rather than replacing it,
# so it's not possible to run a *different* script (the render+run glue
# script) inside that image via CWL's normal command construction --
# whatever CWL passes always ends up as extra arguments to processor.py
# itself. Clearing ENTRYPOINT and using CMD instead (which `docker run`
# *does* fully replace) restores that ability, without touching the
# original repo/image at all -- this just layers on top of it.
FROM heatwise-patch-extraction:latest
ENTRYPOINT []
CMD ["python", "/app/processor.py"]
