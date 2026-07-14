# Deploy failed / Argo CD stuck OutOfSync or Degraded

**Triggers:** a GitHub Actions workflow run fails (red X), or `kubectl describe
application status-api -n argocd` shows anything other than `Synced` + `Healthy`.

## 1. Which layer failed?

| Symptom | Look at |
|---|---|
| `code scan` workflow red | CodeQL found a real finding (check the Security tab), or the Trivy step found a CRITICAL/HIGH CVE with a known fix |
| `deploy site` workflow red | Usually `npm run build` failure (bad Astro/TS), or GitHub Pages isn't enabled yet (Settings → Pages → Source: GitHub Actions) |
| `status-api CI` workflow red | Docker build failure, the Trivy image scan failing the build (see below), or the `git push` step rejected (branch protection requiring PRs) |
| Argo CD app `OutOfSync` | Manifest in `k8s/` doesn't match cluster state — check `kubectl describe application <name> -n argocd`'s `Events` |
| Argo CD app `Degraded` | Pods aren't healthy — see [self-heal.md](./self-heal.md) for the diagnosis/remediation playbook |

## 2. Trivy failed the image scan

`status-api-ci.yml` fails the build on CRITICAL/HIGH vulnerabilities in the built
image. Check the workflow's Trivy step output for which package/CVE. Usually
fixed by bumping the base image (`node:22-alpine` in `apps/status-api/Dockerfile`)
or the affected npm dependency, not by suppressing the check.

## 3. Argo CD access

No tunnel needed — see [local-cluster-access.md](./local-cluster-access.md) for
the full walkthrough. Short version:

```bash
kubectl config use-context docker-desktop
kubectl get applications -n argocd
kubectl describe application status-api -n argocd
```

## 4. status-api CI push rejected

`status-api-ci.yml` commits the new image tag straight to `main` via `git push`.
If branch protection on `main` requires PRs, this step will fail by design — either
relax protection for the `github-actions[bot]` actor, or switch that step to open a
PR instead of pushing directly (trade GitOps auto-deploy speed for review).
