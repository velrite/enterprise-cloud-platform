# Deployment Flow

## Path From Commit to Production

```
Developer commit
  -> GitHub Actions trigger (path-filtered to src/accounts/userservice/**)
  -> Secret scan (Gitleaks) + dependency scan (Trivy)
  -> Build container image, tag by commit SHA
  -> Image scan (Trivy, image mode)
  -> SBOM generation (Syft)
  -> Sign (Cosign, keyless)
  -> Policy gate (OPA/Conftest)
  -> Push to GHCR
  -> ArgoCD detects new manifest state, syncs
  -> Argo Rollouts canary: 25% -> pause -> 50% -> pause -> 100%
  -> AnalysisTemplate checks health at each step
  -> Automatic rollback to last stable ReplicaSet on failed analysis
```

## Real Deploy-Chain Bug That Proved the CI/CD Loop Actually Closes

For a real stretch of this project, the Kubernetes manifest for
`userservice` pointed at a bare, unqualified image reference
(`userservice`, no registry, no tag) — a Kustomize placeholder that was
never wired to the actual pipeline output. The pod would fail
`ErrImagePull` every time. Fixed by pointing the manifest directly at the
real, signed GHCR image tag. This is documented explicitly as **closing a
genuine gap between "the pipeline builds and signs an image" and "the
cluster actually runs that specific image"** — a subtlety worth stating
plainly rather than assuming CI success automatically means the right
image is running.

## Zero-Downtime Deploy — See `docs/reliability/failure-modes.md`

The real, corrected PDB/drain test (39/40 successful requests through a
real node drain) is the evidence for zero-downtime behavior, not a claim
made from the Rollout's canary steps alone.

## Demo Video Script (Written Only — Not Recorded, Out of Scope for This Pass)

1. (0:00-0:30) Architecture diagram, narrate the chain: commit -> scan ->
   sign -> deploy -> observe -> recover.
2. (0:30-2:00) Trigger a real commit, show the Actions run live — all
   stages green.
3. (2:00-3:00) ArgoCD detecting the new image, canary rollout progressing
   (`kubectl get rollout`).
4. (3:00-4:00) Grafana dashboard live during the rollout.
5. (4:00-5:00) kube-bench before/after tables, and the real PDB/drain
   test as evidence this was actually operated, not just deployed once.
6. (5:00-6:00) Close on the honest load-test interpretation and the
   documented technical-debt list — real numbers, real caveats.
