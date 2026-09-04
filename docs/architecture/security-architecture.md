# Security Architecture

## Layers Deployed

- **Vault** (dev mode) — secrets management pattern, not durable (ADR-006).
- **Kyverno** (Audit mode) — admission-time policy checks (ADR-010).
- **Falco** — eBPF-based runtime anomaly detection.
- **Istio mTLS** — `PeerAuthentication` set to `STRICT` for the
  `bank-of-anthos` namespace.
- **IRSA/OIDC** — used concretely for the EBS CSI driver's service account
  (ADR-009); the pattern that would also apply to any future ECR migration
  (ADR-007).
- **Kubernetes RBAC** — least-privilege service accounts.
- **NetworkPolicy** — default-deny, with the AWS VPC CNI enforcement gap
  found and fixed (see below and PM-9).

## What Each Control Is Actually Confirmed to Block (Evidence-Based)

This table distinguishes what was **live-tested** from what is
**configured but unverified** — see `docs/security/security-controls.md`
for the full test transcript this table is drawn from.

| Control | Claim | Evidence status |
|---|---|---|
| RBAC | A namespace-scoped ServiceAccount cannot read secrets in another namespace | **Live-verified**: real `Forbidden` API error returned, not just `kubectl auth can-i` |
| NetworkPolicy default-deny | Cross-namespace traffic is blocked | **Live-verified after a real fix**: first test showed a leak (VPC CNI wasn't enforcing policy by default); after enabling `ENABLE_NETWORK_POLICY=true` on the `aws-node` DaemonSet, the same test failed with `Connection reset by peer` |
| Trivy (image scan) | Blocks CRITICAL/HIGH CVEs before deploy | **Pipeline-verified**: real CVEs (cryptography, pyasn1) were caught and fixed during actual pipeline runs |
| Cosign signing | Only pipeline-built images are trusted | **Pipeline-verified** (signing succeeds); **NOT cluster-admission-verified** — no policy on this cluster currently checks signatures before scheduling a pod |
| Kyverno resource-limits policy | Pods without limits are flagged | **Live-verified**: Falco's own pods triggered a real, logged `PolicyViolation` |
| Istio mTLS | Service-to-service traffic is encrypted | `PeerAuthentication: STRICT` confirmed present via `kubectl get peerauthentication`; **traffic-level telemetry proof was attempted and inconclusive** — the `istio_requests_total` metric was absent from Prometheus at test time (see PM-10) |
| Istio outlier detection / circuit breaking | Repeated 5xx errors eject an unhealthy endpoint | Config confirmed present (`consecutive5xxErrors: 3`, `baseEjectionTime: 30s`); **not observed firing** — 50 rapid real requests all returned 200, so the failure condition needed to trigger ejection was never actually created (see PM-11) |
| Falco runtime detection | Anomalous shell activity inside a container is detected | A real trigger (`kubectl exec ... /bin/sh -c "echo ..."`) was run inside a live `userservice` pod; **no matching Falco log line was found** in the 60s window checked. Documented as an honest inconclusive result, not a pass |

## Blast Radius If Kyverno Is Disabled

New deployments would no longer be checked for resource limits before
admission. This project already experienced real pod-scheduling pressure
from the `t3.small` 11-pod ENI ceiling (PM-2) — an unbounded pod is not a
theoretical risk on this specific cluster, it is the same failure mode
already lived through once.

## Known, Honest Security Gaps

1. Image signature verification is pipeline-only, not admission-enforced.
2. mTLS enforcement is configured but not confirmed via live traffic
   telemetry.
3. Circuit-breaker/outlier-detection behavior has never been observed
   actually firing.
4. Falco's real-time detection was tested once against one specific
   trigger action and did not produce a matching log line in the checked
   window — this does not mean Falco is non-functional, only that this
   specific test did not produce confirming evidence.
5. Vault is dev-mode, not durable.
6. Kyverno is in `Audit`, not `Enforce`.

See `docs/engineering/technical-debt.md` for the full remediation-priority
list.
