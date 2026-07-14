# Self-heal: Claude's pod-health check + remediation playbook

This is what Claude follows when run in a loop (`/loop 5m Follow
runbooks/self-heal.md against the local cluster via the Kubernetes MCP`) to watch
pod health and intervene. It's a **local, active Claude Code session** doing this —
not an unattended cloud daemon. It only runs while that session is open.

The point of writing this down rather than improvising each time: consistent,
safe, minimally-destructive actions, and a clear line between "fix it" and
"report it, don't guess."

## 1. Check

```
kubectl get pods -A
kubectl get applications -n argocd
```

"Unhealthy" means: `CrashLoopBackOff`, `Error`, `ImagePullBackOff`/`ErrImagePull`,
`OOMKilled` in recent events, or `Pending` for more than ~5 minutes. If everything's
`Running`/`1/1` and Argo CD Applications are `Synced`+`Healthy`, report one line
("all healthy") and stop — don't go looking for problems that aren't there.

## 2. Diagnose before acting

For whatever's unhealthy:

```
kubectl describe pod <pod> -n <ns>          # Events section has the real reason
kubectl logs <pod> -n <ns> --previous       # if it has restarted
```

## 3. Remediate — per failure mode

**CrashLoopBackOff / Error** (app-level crash):
- Read the crash reason from logs. If it's clearly a bad deploy (recent image
  tag bump in `k8s/status-api/kustomization.yaml`'s git history correlates with
  the crash start), do both:
  1. Immediate mitigation: `kubectl rollout undo deployment/status-api -n default`
     to restore service fast.
  2. Fix the source: revert `kustomization.yaml`'s image tag to the last-known-good
     value and `git commit` + `git push` — otherwise Argo CD's `selfHeal` will
     just reapply the broken version from git and undo your `rollout undo`.
- If the cause isn't obviously a bad deploy (looks like an app bug), report it
  with the log excerpt rather than guessing at a fix.

**ImagePullBackOff / ErrImagePull**:
- Check the exact error in pod Events. Common causes here specifically:
  - `ghcr-pull-secret` missing or the PAT inside it expired/was revoked — see
    [local-cluster-access.md](./local-cluster-access.md) to recreate it.
  - The tag genuinely doesn't exist yet (race between `status-api-ci.yml`
    pushing and Argo CD syncing) — usually resolves itself within a minute;
    don't intervene, just note it and recheck next cycle.

**OOMKilled**:
- Bump `resources.limits.memory` in `k8s/status-api/deployment.yaml` (a modest
  increase, not an arbitrary huge one), commit, push. Note in your report that
  you changed a real resource limit.

**Pending > 5 min**:
- `kubectl describe pod` for scheduling events. On a single local node this is
  almost always a resource ceiling — check `kubectl describe node` and Docker
  Desktop's own memory/CPU allocation (Settings → Resources). Report this;
  don't try to "fix" a hardware ceiling by yourself.

**Argo CD Application stuck OutOfSync / ComparisonError**:
- `kubectl describe application <name> -n argocd`, check the error. A transient
  `repo-server` connection error self-heals within a cycle or two — don't act,
  just note it. A genuine manifest error (bad YAML, kustomize build failure)
  needs a real fix to the source files, not a cluster-side workaround.

## 4. Boundaries

- Never delete/recreate a resource as a first move — that's the most destructive
  option and should be a last resort, not a reflex.
- If the same failure recurs after you've already remediated it once this
  session, **stop and report** instead of repeating the same fix — a recurring
  failure means the fix didn't address the real cause.
- Any change to files (rolling back an image tag, bumping a resource limit)
  should be a real, clearly-described git commit — never a silent cluster-only
  patch that git and the cluster then disagree about.

## 5. Report

One or two lines per cycle: what you checked, what (if anything) was wrong, what
you did about it. Silence is fine when everything's healthy — don't manufacture
a report out of nothing.
