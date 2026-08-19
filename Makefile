# Single entry point for every check that runs in continuous integration, so that a
# failure can always be reproduced locally with the same command the pipeline used.
#
# Run `make help` for the available targets.

SHELL := /usr/bin/env bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := help

IMAGE ?= demonstration-service:local
CLUSTER_NAME ?= demonstration
NAMESPACE ?= demonstration
APP_VERSION ?= $(shell sed -n 's/^version = "\(.*\)"/\1/p' app/pyproject.toml)
COMMIT_SHA ?= $(shell git rev-parse --short HEAD 2>/dev/null || echo unknown)
TERRAFORM_DIRS := $(shell find terraform -name versions.tf -exec dirname {} \; | sort)

.PHONY: help
help: ## Show this help
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

# ---------------------------------------------------------------------------
# Application
# ---------------------------------------------------------------------------

.PHONY: install
install: ## Install the application with its development dependencies
	python3 -m pip install --editable 'app[dev]'

.PHONY: lint-app
lint-app: ## Lint and type-check the application
	cd app && ruff check .
	cd app && ruff format --check .
	cd app && mypy

.PHONY: test-app
test-app: ## Run the application test suite with its coverage gate
	cd app && pytest

# ---------------------------------------------------------------------------
# Infrastructure as code
# ---------------------------------------------------------------------------

.PHONY: lint-terraform
lint-terraform: ## Check formatting and validate every Terraform module and environment
	terraform fmt -check -recursive terraform
	@for dir in $(TERRAFORM_DIRS); do \
		echo "==> validating $$dir"; \
		terraform -chdir=$$dir init -backend=false -input=false -no-color > /dev/null; \
		terraform -chdir=$$dir validate -no-color; \
	done

.PHONY: lint-terraform-rules
lint-terraform-rules: ## Lint the Terraform with the AWS ruleset
	@command -v tflint > /dev/null || { echo "tflint is not installed; see docs/local-development.md"; exit 1; }
	tflint --init
	tflint --recursive --format compact --minimum-failure-severity=warning

.PHONY: scan-terraform
scan-terraform: ## Scan the Terraform for misconfiguration
	docker run --rm --volume "$(CURDIR):/repo" --workdir /repo bridgecrew/checkov:latest \
		--directory terraform --framework terraform --quiet --compact --output cli

.PHONY: test-terraform
test-terraform: ## Run the Terraform unit tests against a mocked provider
	@for dir in $$(find terraform/modules -maxdepth 1 -mindepth 1 -type d | sort); do \
		echo "==> testing $$dir"; \
		terraform -chdir=$$dir init -backend=false -input=false -no-color > /dev/null; \
		terraform -chdir=$$dir test -no-color; \
	done

# ---------------------------------------------------------------------------
# Container
# ---------------------------------------------------------------------------

.PHONY: build
build: ## Build the container image and confirm it serves traffic
	docker build \
		--file docker/Dockerfile \
		--tag $(IMAGE) \
		--build-arg APP_VERSION=$(APP_VERSION) \
		--build-arg COMMIT_SHA=$(COMMIT_SHA) \
		.
	@scripts/container-smoke.sh $(IMAGE)

.PHONY: scan
scan: ## Scan the image for known vulnerabilities
	docker run --rm \
		--volume /var/run/docker.sock:/var/run/docker.sock \
		aquasec/trivy:latest image --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 $(IMAGE)

# ---------------------------------------------------------------------------
# Kubernetes
# ---------------------------------------------------------------------------

.PHONY: lint-k8s
lint-k8s: ## Render every overlay and validate it against the upstream schemas
	@for overlay in k8s/overlays/*; do \
		echo "==> rendering $$overlay"; \
		kubectl kustomize $$overlay > /dev/null; \
	done
	@command -v kubeconform > /dev/null || { echo "kubeconform is not installed; see docs/local-development.md"; exit 1; }
	@for overlay in k8s/overlays/*; do \
		echo "==> validating $$overlay"; \
		kubectl kustomize $$overlay | kubeconform -strict -summary -ignore-missing-schemas; \
	done

.PHONY: k8s-up
k8s-up: ## Provision the local cluster and deploy the development overlay
	scripts/kind-up.sh

.PHONY: verify
verify: ## Assert the deployed workload honours its contracts
	scripts/smoke-test.sh

.PHONY: k8s-down
k8s-down: ## Remove the local cluster
	scripts/kind-down.sh

# ---------------------------------------------------------------------------
# Aggregates
# ---------------------------------------------------------------------------

.PHONY: lint
lint: lint-app lint-terraform lint-terraform-rules lint-k8s ## Run every static check

.PHONY: test
test: test-app test-terraform ## Run every test suite

.PHONY: all
all: lint test build k8s-up verify ## Run the full pipeline end to end

.PHONY: clean
clean: k8s-down ## Remove the local cluster and build artefacts
	docker rmi $(IMAGE) 2>/dev/null || true
	find . -type d -name __pycache__ -prune -exec rm -rf {} + 2>/dev/null || true
	rm -rf app/.pytest_cache app/.mypy_cache app/.ruff_cache app/.coverage
