# Lessons Learned

- **A `NetworkPolicy` object existing does not mean it is enforced.**
  Verify the CNI's actual enforcement capability (PM-9) before trusting
  the policy is doing anything.
- **A DaemonSet pod stuck `Pending` is not automatically a
  "scale the node group" problem.** Check `nodeAffinity` and the specific
  bound node's real pod count first (PM-2) — more nodes elsewhere does
  nothing if the bound node itself is full.
- **A single pod's resource request exceeding a single node's capacity
  cannot be fixed by horizontal scaling.** More `t3.small` nodes never
  helps if no individual node is big enough for one pod (Istio `istiod`
  case, ADR-005) — this needed a smaller footprint, not more capacity.
- **`kubectl port-forward` and self-calling `kubectl exec` do not traverse
  a service mesh.** Testing mesh behavior (fault injection, mTLS,
  circuit-breaking) requires a genuine separate client pod actually
  inside the mesh, calling via real DNS.
- **Never trust `sleep N` as proof an async operation (port-forward, Helm
  install, DaemonSet rollout) is actually ready.** Poll for the real
  confirmation signal in the log/status before proceeding (PM-12).
- **Chart version drift breaks previously-working values files.** When a
  `helm install` fails with a validation error naming a specific missing
  field, the chart's own error text is almost always the exact fix — read
  it rather than guessing (PM-6c, PM-8).
- **A failed `helm install` can leave a stale release record that blocks
  retrying under the same name**, even with zero real resources deployed.
  Check `helm list -n <ns> -a` before assuming a clean slate (PM-6b).
- **Rewriting a fork's upstream git history to "fix" inherited secret
  scanner findings is the wrong move.** Scope the scanner to what you
  actually own instead (PM-5).
- **GitHub Pages CDN connectivity issues from this environment have
  consistently been intermittent, not permanent** — a short retry loop
  resolves them; don't escalate to deep network diagnosis before trying
  that first.
- **A recurring WSL2 DNS failure is a known, proactively-checkable issue
  on this project (PM-13)** — check it at the start of every session, do
  not wait for it to break and cost debugging time again.
- **Kustomize `resources:` lists silently ignore files not listed in
  them.** ArgoCD will happily report `Synced`/`Healthy` while actually
  working from an incomplete file set — validate locally with
  `kubectl kustomize <path>` before trusting a sync status.
- **A "successful" CI/CD pipeline does not guarantee the cluster is
  running the image the pipeline built.** These are two separate claims;
  verify the actual deployed manifest points at the actual signed image.
- **Do not claim a security control works from its configuration alone
  when a live test is feasible.** This project's own deep-verification
  pass found one real, previously-unnoticed gap (NetworkPolicy
  enforcement) specifically because it tested behavior, not just checked
  that YAML existed.
