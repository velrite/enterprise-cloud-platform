# Debugging History (Narrative Summary)

This project was built across multiple working sessions, each starting
from either a live cluster or a full teardown (the operator tore the
cluster down at the end of most sessions to control AWS Free Plan credit
spend — a deliberate, repeated cost-discipline decision, not an accident).

## Rough Chronology

1. **Foundations**: AWS account setup, IAM off-root with MFA, Terraform
   remote state (S3+DynamoDB, never destroyed), VPC, first EKS cluster.
   Hit and resolved: root-vs-IAM login confusion, a console-password-never-
   enabled IAM user, `t3.medium` blocked by Free Plan (PM-7), EKS
   Free-Tier-node-group failures, `access_config` requirements for
   API-based EKS access entries.
2. **CI/CD pipeline**: built stage by stage against a real fork of Bank of
   Anthos's `userservice`. Hit and resolved: fork-vs-upstream PR routing
   confusion (GitHub defaults PRs on a fork to target the *upstream*
   repo), Actions disabled by default on forks, wrong Python tooling
   assumptions (`uv` not `pip`, `pylint` not `flake8`, Python 3.14 not
   3.11), a guessed-and-wrong Trivy action version, the Gitleaks
   full-history false-positive storm (PM-5), two real CVEs found and
   fixed by Trivy, an invalid Rego policy syntax bug, and a buggy
   installed `gh` CLI version that silently merged a stale commit instead
   of a branch's real tip (worked around by using plain `git merge`
   thereafter).
3. **GitOps + canary**: ArgoCD and Argo Rollouts installed, `userservice`
   converted from a plain `Deployment` to a `Rollout` — which silently
   dropped both the `Service` object (breaking in-cluster DNS entirely,
   a multi-hour debugging chain eventually traced to a missing Kustomize
   `resources:` entry) and the JWT secret filename remap (PM-4). The
   automatic-rollback capability was proven for real when a genuine bug
   in the `AnalysisTemplate` caused repeated failures and Argo Rollouts
   correctly reverted on its own.
4. **Service mesh**: Istio's default `istiod` memory request (2Gi)
   exceeded what a single `t3.small` node could ever provide — diagnosed
   precisely (not guessed) by checking the deployment's actual resource
   request against node allocatable capacity, fixed with an explicit
   `--set values.pilot.resources...` override (ADR-005). Fault injection
   was proven with real curl timing (~5s with fault vs ~0.02s without)
   only after discovering that `kubectl port-forward`/`kubectl exec`
   calling a pod from itself never actually traverses the mesh — a
   genuine, separate in-mesh test client was required.
5. **Security hardening + observability**: Vault, Kyverno, Falco, then
   Prometheus/Grafana, then Loki/Tempo/OpenTelemetry. This phase surfaced
   the DaemonSet-nodeAffinity pattern (PM-2) twice, the missing EBS CSI
   driver (PM-3), multiple Helm chart version-drift breakages (PM-6c,
   PM-8), and the GitHub Pages intermittent-connectivity pattern that
   turned out to be transient rather than a hard network block.
6. **Deep live security verification**: a self-designed, multi-round test
   suite run directly against the live cluster (RBAC boundaries,
   NetworkPolicy enforcement, Falco real-time detection, PDB under a real
   drain, unsigned-image admission, mTLS telemetry, circuit-breaker
   firing, SBOM queryability) — this is where the real VPC CNI
   NetworkPolicy enforcement gap (PM-9) was found and fixed, and where
   the honest gaps around mTLS telemetry and circuit-breaker evidence
   were surfaced rather than assumed away.
7. **Load testing and cost analysis**: real `ab` results and real AWS
   CLI cost data, after two tooling failures (PM-12).

## Recurring, Cross-Cutting Lessons

See `docs/engineering/lessons-learned.md` for the distilled, non-narrative
version of everything above.
