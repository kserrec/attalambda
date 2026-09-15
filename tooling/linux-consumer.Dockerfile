# Test-only preparation. The caller supplies the existing pinned Ubuntu digest;
# artifact acceptance runs afterward without network access or root privileges.
ARG BASE_IMAGE
FROM ${BASE_IMAGE}
RUN apt-get update \
    && apt-get install -y --no-install-recommends python3 \
    && rm -rf /var/lib/apt/lists/*
