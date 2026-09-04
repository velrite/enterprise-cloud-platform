# Supply Chain Security

## Pipeline Stages (as actually implemented)

1. **Source control trigger** — PR/push to `main`, path-filtered to
   `src/accounts/userservice/**` only.
2. **Secret scan** — Gitleaks, `--no-git --source=<path>`. Originally run
   with `fetch-depth: 0` (full git history), which returned 60 "leaks" —
   years-old dummy credentials in Google's own upstream demo manifests, not
   anything this project added and not live secrets. Rescoped to current
   files only in the owned service folder. One documented, justified
   allowlist entry remains for a Kubernetes secret *reference* (not an
   embedded secret) that the scanner still flags as a false positive.
3. **Dependency scan** — Trivy filesystem mode. Caught and fixed two real
   CVEs during actual operation: `cryptography` (49.0.0 → 50.0.0,
   CVE-2026-69247) and `pyasn1` (0.6.3 → 0.6.4, three CVEs). A separate
   Debian base-image CVE set was found to have **no available upstream fix
   yet** and is suppressed with `ignore-unfixed: true` — a documented,
   justified exception, not blanket suppression.
4. **Build** — Docker image, tagged by commit SHA, pushed to GHCR.
5. **Image scan** — Trivy image mode, blocks on CRITICAL/HIGH.
6. **SBOM generation** — Syft, SPDX format. **Independently re-verified
   live** against the actual deployed image (not just the CI artifact):
   1241 packages enumerated, `flask 3.1.3` confirmed present and queryable.
7. **Sign** — Cosign, keyless via GitHub OIDC. No long-lived signing key
   exists anywhere in this project.
8. **Policy gate** — OPA/Conftest, checks resource limits, non-root,
   rejects `:latest` tags.
9. **Deploy** — ArgoCD syncs the GitOps repo; Argo Rollouts performs a
   canary (25% → 50% → 100%, with pauses) with automatic rollback on
   failed analysis.

## Real Incident That Proved the Rollback Works

A genuine bug in the `AnalysisTemplate`'s `successCondition` PromQL syntax
caused the analysis to error repeatedly during a real canary rollout. Argo
Rollouts correctly detected the failure threshold and reverted to the last
stable ReplicaSet automatically, keeping the service available (`2/2`)
throughout. This was not staged — it happened because of a real
configuration mistake, which makes it stronger evidence than a scripted
demo would have been.

## The One Real, Unclosed Gap

**Image signature verification is enforced in the CI pipeline (a build
cannot proceed to deploy without a valid Cosign signature) but is NOT
enforced at cluster admission.** A live test confirmed no ClusterPolicy or
OPA policy on this cluster currently checks signatures before scheduling a
pod. The realistic remediation is a Kyverno `verifyImages` policy — not
implemented, listed in `docs/engineering/technical-debt.md`.
