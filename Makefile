# ------------------------------------------------------------------------------
# base-webapp -- package + publish to a local Harbor (OCI)
# ------------------------------------------------------------------------------
# This Makefile's whole job is packaging and publishing this one chart to a
# LOCAL Harbor. It does not install/bootstrap Harbor itself (that stays
# platform infrastructure, owned by the k8s-deployment-strategy monorepo) --
# this repo only needs to know Harbor's address to publish to.
#
# GitHub Actions' hosted runners can't reach $(HARBOR_HOST) (it's only
# routable inside the local OrbStack cluster), so publish-chart is run by
# hand from a machine that can. The public counterpart -- publishing to GHCR
# -- lives in .github/workflows/publish-chart.yaml and runs on version tags.
# Argo CD (in the consuming k8s-deployment-strategy-gitops repo) pulls the
# chart straight from Harbor in-cluster.

# Local Harbor this Makefile publishes to. Override to target another
# instance, e.g. `make publish-chart HARBOR_HOST=harbor.example.local`.
# Plain HTTP on purpose (see the --plain-http flags below).
HARBOR_HOST           ?= harbor.k8s.orb.local
HARBOR_CHARTS_PROJECT ?= charts
HARBOR_ADMIN_USER     ?= admin
# No default on purpose -- a real value here would be a plaintext credential
# committed to git. Pass it on the command line or export it in your shell,
# e.g. `HARBOR_ADMIN_PASSWORD=... make publish-chart`.
HARBOR_ADMIN_PASSWORD ?=

# Set VERIFY=true to also run verify-chart-published right after publishing.
# Off by default: right after a push it compares what was just pushed against
# itself, so it's most useful run on its own, *before* publishing, to catch a
# template edit that wasn't paired with a version bump.
VERIFY ?= false

CHART_DIR      ?= .
CHART_DIST_DIR ?= dist

.PHONY: help harbor-chart-project release package-chart publish-chart verify-chart-published

help: ## Show this help message
	@echo "Available targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2}'

# Public: anonymous pull is how both qrcode-api's Argo CD Application and this
# monorepo's own local smoke-test target consume the published chart -- no
# Harbor credential registered/passed for reads anywhere downstream (verified
# live: a plain `helm show chart oci://.../base-webapp --plain-http`, no
# --username/--password, worked once this project's visibility was flipped to
# public). Creating still needs admin auth; reading the published chart doesn't.
harbor-chart-project: ## Create the Harbor "charts" project for chart artifacts (idempotent, public)
	@echo "==> Checking for Harbor project '$(HARBOR_CHARTS_PROJECT)'..."
	@count=$$(curl -sf -u $(HARBOR_ADMIN_USER):$(HARBOR_ADMIN_PASSWORD) \
		"http://$(HARBOR_HOST)/api/v2.0/projects?name=$(HARBOR_CHARTS_PROJECT)" | jq 'length'); \
	if [ "$$count" -gt 0 ]; then \
		echo "==> Project '$(HARBOR_CHARTS_PROJECT)' already exists, skipping."; \
	else \
		echo "==> Creating project '$(HARBOR_CHARTS_PROJECT)'..."; \
		curl -sf -u $(HARBOR_ADMIN_USER):$(HARBOR_ADMIN_PASSWORD) \
			-X POST "http://$(HARBOR_HOST)/api/v2.0/projects" \
			-H "Content-Type: application/json" \
			-d '{"project_name": "$(HARBOR_CHARTS_PROJECT)", "public": true}'; \
		echo "==> Project '$(HARBOR_CHARTS_PROJECT)' created."; \
	fi

# Cuts a release locally: sets Chart.yaml's version, lints, commits and tags
# vVERSION. It never pushes -- pushing the tag is what triggers the GHCR
# workflow, so that stays an explicit, separate step. If VERSION already equals
# Chart.yaml's version (bumped by hand in an earlier commit), only the tag is
# created. Usage: `make release VERSION=0.8.0`.
release: ## Bump Chart.yaml to VERSION, lint, commit and tag vVERSION locally (does not push)
	@if [ -z "$(VERSION)" ]; then echo "VERSION is required, e.g. make release VERSION=0.8.0"; exit 1; fi
	@echo "$(VERSION)" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$$' || { echo "VERSION '$(VERSION)' is not a plain semver (X.Y.Z)"; exit 1; }
	@if [ -n "$$(git status --porcelain)" ]; then echo "Working tree is not clean -- commit or stash your changes first."; exit 1; fi
	@branch=$$(git rev-parse --abbrev-ref HEAD); \
	if [ "$$branch" != "main" ]; then echo "Releases are cut from main (currently on '$$branch')."; exit 1; fi
	@if git rev-parse -q --verify "refs/tags/v$(VERSION)" >/dev/null; then echo "Tag v$(VERSION) already exists."; exit 1; fi
	@current=$$(grep '^version:' $(CHART_DIR)/Chart.yaml | awk '{print $$2}'); \
	if [ "$$(printf '%s\n%s\n' "$$current" "$(VERSION)" | sort -V | tail -n1)" != "$(VERSION)" ]; then \
		echo "VERSION $(VERSION) is lower than the current Chart.yaml version $$current."; exit 1; \
	fi; \
	if [ "$$current" != "$(VERSION)" ]; then \
		sed -i.bak "s/^version:.*/version: $(VERSION)/" $(CHART_DIR)/Chart.yaml && rm -f $(CHART_DIR)/Chart.yaml.bak; \
	fi
	@helm lint $(CHART_DIR)
	@if [ -n "$$(git status --porcelain)" ]; then \
		git add $(CHART_DIR)/Chart.yaml && git commit -m "chore: release v$(VERSION)"; \
	fi
	@git tag -a "v$(VERSION)" -m "v$(VERSION)"
	@echo "==> Tagged v$(VERSION) locally. To publish to GHCR:"
	@echo "    git push origin main v$(VERSION)"

package-chart: ## Package this chart into dist/base-webapp-<version>.tgz
	@mkdir -p $(CHART_DIST_DIR)
	@helm package $(CHART_DIR) -d $(CHART_DIST_DIR)

# Credentials go straight to "helm push"/"helm pull" via --username/--password
# rather than a separate "helm registry login" step: on macOS, login persists
# the credential through docker-credential-osxkeychain, which conflicts with
# stale/foreign keychain entries left behind by earlier Harbor installs and
# fails outright ("item already exists in the keychain"). Inline flags avoid
# that shared, stateful credential store entirely and behave identically.
publish-chart: package-chart harbor-chart-project ## Push the packaged chart to Harbor as an OCI artifact
	@chart_name=$$(grep '^name:' $(CHART_DIR)/Chart.yaml | awk '{print $$2}'); \
	chart_tgz=$$(ls -t $(CHART_DIST_DIR)/$$chart_name-*.tgz | head -n1); \
	chart_version=$$(basename $$chart_tgz .tgz | sed "s/^$$chart_name-//"); \
	echo "==> Publishing $$chart_tgz to oci://$(HARBOR_HOST)/$(HARBOR_CHARTS_PROJECT)..."; \
	helm push $$chart_tgz "oci://$(HARBOR_HOST)/$(HARBOR_CHARTS_PROJECT)" \
		--plain-http --username $(HARBOR_ADMIN_USER) --password $(HARBOR_ADMIN_PASSWORD); \
	echo "==> Published: oci://$(HARBOR_HOST)/$(HARBOR_CHARTS_PROJECT)/$$chart_name:$$chart_version"
	@if [ "$(VERIFY)" = "true" ]; then $(MAKE) verify-chart-published; fi

# Catches drift by re-rendering whatever Harbor has at the local Chart.yaml
# version and diffing it against the local working tree -- if someone edited
# templates without bumping the version, this fails loudly instead of
# silently shipping stale behavior under an old tag.
verify-chart-published: ## Diff local chart templates against the matching version already published in Harbor, if any (fails loudly on mismatch)
	@if [ -z "$(HARBOR_ADMIN_PASSWORD)" ]; then \
		echo "HARBOR_ADMIN_PASSWORD must be set (no default -- see the comment by its declaration)."; \
		exit 1; \
	fi
	@chart_name=$$(grep '^name:' $(CHART_DIR)/Chart.yaml | awk '{print $$2}'); \
	chart_version=$$(grep '^version:' $(CHART_DIR)/Chart.yaml | awk '{print $$2}'); \
	tmp_dir=$$(mktemp -d); \
	echo "==> Checking whether $$chart_name:$$chart_version is already published in Harbor..."; \
	if helm pull "oci://$(HARBOR_HOST)/$(HARBOR_CHARTS_PROJECT)/$$chart_name" \
		--version "$$chart_version" --plain-http \
		--username $(HARBOR_ADMIN_USER) --password $(HARBOR_ADMIN_PASSWORD) \
		-d "$$tmp_dir" >/dev/null 2>&1; then \
		echo "==> Found published $$chart_name:$$chart_version -- diffing rendered templates against the local working tree..."; \
		mkdir -p "$$tmp_dir/extracted"; \
		tar xzf "$$tmp_dir/$$chart_name-$$chart_version.tgz" -C "$$tmp_dir/extracted"; \
		helm template "$$tmp_dir/extracted/$$chart_name" > "$$tmp_dir/published.yaml" 2>&1; \
		helm template $(CHART_DIR) > "$$tmp_dir/local.yaml" 2>&1; \
		if diff -u "$$tmp_dir/published.yaml" "$$tmp_dir/local.yaml" > "$$tmp_dir/diff.txt"; then \
			echo "==> OK: published $$chart_name:$$chart_version renders identically to the local working tree."; \
			rm -rf "$$tmp_dir"; \
		else \
			echo ""; \
			echo "!! MISMATCH: Harbor's $$chart_name:$$chart_version does not render identically to the"; \
			echo "!! local working tree at the same version. Templates were edited without bumping"; \
			echo "!! Chart.yaml's version -- bump the version and republish."; \
			echo ""; \
			cat "$$tmp_dir/diff.txt"; \
			rm -rf "$$tmp_dir"; \
			exit 1; \
		fi; \
	else \
		echo "==> $$chart_name:$$chart_version is not published in Harbor yet (expected for a pending new version) -- nothing to verify."; \
		rm -rf "$$tmp_dir"; \
	fi
