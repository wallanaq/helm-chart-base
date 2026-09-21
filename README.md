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

```bash
HARBOR_ADMIN_PASSWORD=... make publish-chart
```

Packages the chart and pushes it to Harbor (`oci://harbor.k8s.orb.local/charts/base-webapp`)
as an OCI artifact, plain HTTP (no TLS) -- this is a local OrbStack lab cluster, not a
public registry. `verify-chart-published` runs automatically afterward, diffing the
freshly-published artifact's rendered templates against the local working tree and failing
loudly on any mismatch (a template edited without a matching version bump would otherwise
ship silently under a stale tag).

Harbor itself is **not** owned by this repo -- it's platform infrastructure, installed and
managed elsewhere (currently the `k8s-deployment-strategy` monorepo's Makefile / Argo CD;
see that repo). This repo only needs to know Harbor's address to publish to.

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
