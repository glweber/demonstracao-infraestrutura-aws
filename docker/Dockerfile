# syntax=docker/dockerfile:1.12
#
# Multi-stage build for the demonstration service.
#
# Stage 1 resolves and installs dependencies into a self-contained virtual
# environment. Stage 2 copies only that environment and the interpreter, so build
# toolchains, package caches and source archives never reach the published layer.
#
# The base image carries both a tag and a digest. The digest is what pins the build:
# a tag is mutable and can be repointed at different content, whereas a digest is
# content-addressed and therefore reproducible.
#
# The tag is not decoration. A digest-only reference names no release line, so an
# automated dependency update has nothing to track and resolves against the default
# tag instead — which silently proposed a jump from Python 3.12 on bookworm to 3.14
# on trixie. Naming the tag confines any proposed digest to this release line.

# ---------------------------------------------------------------------------
# Stage 1 — build
# ---------------------------------------------------------------------------
FROM python:3.14-slim-bookworm@sha256:23c59390fc717bf09f9336908199a0ae75d9c4264bf296123f94ad772fea3b52 AS build

ENV PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1 \
    PYTHONDONTWRITEBYTECODE=1

WORKDIR /src

# The manifest is copied before the sources so that the dependency layer is reused
# whenever application code changes but the declared dependencies do not.
COPY app/pyproject.toml ./pyproject.toml
COPY app/src ./src

# NOTE: direct dependencies are pinned to exact versions in pyproject.toml, and
# Dependabot proposes upgrades weekly. Transitive dependencies are resolved at build
# time. Introducing a hash-pinned lock file ("pip-compile --generate-hashes" or
# "uv lock") is the upgrade path when full supply-chain reproducibility is required.
RUN python -m venv /opt/venv \
    && /opt/venv/bin/pip install --no-cache-dir --upgrade pip setuptools wheel \
    && /opt/venv/bin/pip install --no-cache-dir . \
    && /opt/venv/bin/pip uninstall --yes pip setuptools wheel

# The installer and its build tools are removed once installation is complete. A
# running service never needs to install a package, so shipping them only widens
# the vulnerability surface and gives an attacker a package manager to work with.

# ---------------------------------------------------------------------------
# Stage 2 — runtime
# ---------------------------------------------------------------------------
FROM python:3.14-slim-bookworm@sha256:23c59390fc717bf09f9336908199a0ae75d9c4264bf296123f94ad772fea3b52 AS runtime

# Build metadata supplied by the build system; surfaced by the service at "/" and
# recorded as OCI annotations so that a running image can be traced to its source.
ARG APP_VERSION=0.0.0-dev
ARG COMMIT_SHA=unknown
ARG BUILD_TIMESTAMP=unknown

LABEL org.opencontainers.image.title="demonstration-service" \
      org.opencontainers.image.description="Reference HTTP workload for the AWS infrastructure demonstration" \
      org.opencontainers.image.version="${APP_VERSION}" \
      org.opencontainers.image.revision="${COMMIT_SHA}" \
      org.opencontainers.image.created="${BUILD_TIMESTAMP}" \
      org.opencontainers.image.licenses="Apache-2.0" \
      org.opencontainers.image.source="https://github.com/glweber/demonstracao-infraestrutura-aws"

ENV PATH="/opt/venv/bin:${PATH}" \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    APP_VERSION="${APP_VERSION}" \
    APP_COMMIT_SHA="${COMMIT_SHA}" \
    APP_PORT=8000

# A dedicated unprivileged account with a fixed, high UID. The numeric identity is
# what "runAsUser" and "runAsNonRoot" assert against in the pod security context, so
# it must not be left to the base image to allocate.
RUN groupadd --gid 10001 service \
    && useradd --uid 10001 --gid 10001 --no-create-home --shell /usr/sbin/nologin service

COPY --from=build --chown=root:root /opt/venv /opt/venv

USER 10001:10001
WORKDIR /opt/venv

EXPOSE 8000

# The runtime image carries no shell utilities such as curl, so the check is written
# against the interpreter that is necessarily present. Kubernetes drives its own
# probes; this instruction covers plain container runtimes and local execution.
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD ["python", "-c", "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/healthz', timeout=2).status == 200 else 1)"]

ENTRYPOINT ["python", "-m", "uvicorn"]
CMD ["service.main:app", "--host", "0.0.0.0", "--port", "8000", "--no-server-header"]
