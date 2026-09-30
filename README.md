# helm-chart-base

Standalone home for the `base-webapp` Helm chart: a generic, reusable base chart for HTTP
services (Deployment/Rollout, Service, optional ServiceAccount, HTTPRoute via Gateway API,
HorizontalPodAutoscaler, optional Istio mTLS, optional Argo Rollouts canary support). Not
tied to any one application -- a consuming values file (e.g. `qrcode-api`'s, in the
[k8s-deployment-strategy-gitops][gitops-repo] repo) supplies the application-specific
pieces.

Extracted from the `k8s-deployment-strategy` monorepo's `charts/base-webapp/` (this repo
continues that chart's existing version sequence -- see `Chart.yaml` -- rather than
resetting to `1.0.0`; the chart's name and published history in Harbor are unchanged by
where its source is maintained).

## What's here

Just the chart itself, at the repo root (not nested under a `charts/` subfolder -- this
repo's whole purpose is one chart), plus a lean `Makefile` to package and publish it:

```
helm-chart-base/
  Chart.yaml
  values.yaml
  values.schema.json
  templates/
  Makefile
```

## Publishing

The chart is published to two places, independently.

### Local Harbor (by hand)

```bash
HARBOR_ADMIN_PASSWORD=... make publish-chart
```

Packages the chart and pushes it to the local Harbor
(`oci://harbor.k8s.orb.local/charts/base-webapp`) as an OCI artifact, plain HTTP (no TLS) --
this is a local OrbStack lab cluster, not a public registry. Override the target with
`HARBOR_HOST`, `HARBOR_CHARTS_PROJECT` and `HARBOR_ADMIN_USER`.

`make verify-chart-published` diffs the rendered templates of what Harbor has at the local
`Chart.yaml` version against the working tree and fails loudly on a mismatch (a template
edited without a matching version bump would otherwise ship silently under a stale tag).
It's opt-in after a publish (`make publish-chart VERIFY=true`) and most useful run on its
own *before* publishing.

Harbor itself is **not** owned by this repo -- it's platform infrastructure, installed and
managed elsewhere (currently the `k8s-deployment-strategy` monorepo's Makefile / Argo CD;
see that repo). This repo only needs to know Harbor's address to publish to.

### GHCR (GitHub Actions)

`.github/workflows/publish-chart.yaml` publishes to `oci://ghcr.io/<owner>/charts/base-webapp`
when a version tag is pushed. The tag must match `version:` in `Chart.yaml`. `make release`
keeps the two in sync:

```bash
make release VERSION=0.8.0      # sets Chart.yaml, lints, commits, tags v0.8.0 (local only)
git push origin main v0.8.0     # pushing the tag triggers the GHCR workflow
make publish-chart              # optional: also publish this version to the local Harbor
```

`make release` requires a clean working tree on `main`, a plain `X.Y.Z` version that is not
lower than the current one, and a tag that doesn't exist yet. If `VERSION` already equals
`Chart.yaml`'s version, it only creates the tag.

The workflow authenticates with the built-in `GITHUB_TOKEN`. New GHCR packages start
private; make the package public once in its GitHub settings if consumers need anonymous
pulls.

## Consumers

`qrcode-api` (in [k8s-deployment-strategy-gitops][gitops-repo]) consumes this chart as a
versioned OCI artifact pulled from Harbor -- `oci://harbor.k8s.orb.local/charts/base-webapp`,
pinned to a specific `targetRevision` -- not by file path. That means this repo's own
history (commits, branches, where it's cloned from) has no bearing on how the chart is
consumed downstream; only the published OCI artifact does.

[gitops-repo]: <!-- TODO: fill in once this repo and the gitops repo are actually pushed
somewhere reachable by both -- see the "what's left manual" note in that extraction's
history -->

## Status

Not yet pushed anywhere. Currently a local-only git repository at
`../helm-chart-base` (sibling of the `k8s-deployment-strategy` monorepo). Pushing to
Forgejo and GitHub is a manual, one-time step (same process used for the gitops repo:
create the org/repo on Forgejo, generate a scoped access token, push to both remotes) --
not done as part of the extraction itself.
