# Technical Debt — Honest Assessment

Each item: current state -> risk -> why it exists -> recommended
remediation. Nothing below is invented; every item traces to a real,
documented finding elsewhere in this documentation set.

## 1. Vault runs in dev mode

**Current state**: `server.dev.enabled=true`, auto-unsealed, in-memory,
not durable across pod restarts.
**Risk**: any real secret stored here is lost on restart; not viable for
anything beyond demonstrating the pattern.
**Why it exists**: explicit time trade-off (ADR-006), documented from the
start, not discovered later.
**Remediation**: real init/unseal ceremony, persistent storage backend,
HA mode. Not started.

## 2. Image signature verification is pipeline-only, not admission-enforced

**Current state**: Cosign signs every image in CI; no cluster-side policy
verifies that signature before scheduling.
**Risk**: an image that somehow bypassed the pipeline (manual `kubectl
apply` with a different image reference, compromised registry) would not
be blocked at the cluster level.
**Why it exists**: not yet implemented; confirmed absent via a live test
(`docs/security/security-controls.md`, Test 5), not assumed.
**Remediation**: a Kyverno `verifyImages` (or equivalent OPA) policy.

## 3. mTLS enforcement not confirmed via live traffic telemetry

**Current state**: `PeerAuthentication: STRICT` confirmed present via
config; `istio_requests_total` metric was absent from Prometheus at test
time, so the traffic-level proof was not obtained.
**Risk**: low functional risk (STRICT mode is a well-understood Istio
primitive), but this documentation set cannot currently point to live
evidence of encrypted traffic between services, only to the policy
object.
**Remediation**: re-run the mTLS metric query after confirming
`istio_requests_total` is actually being scraped (may require checking
Prometheus's ServiceMonitor/scrape config for the Istio namespace, not
attempted in this session).

## 4. Circuit breaker / outlier detection unverified under real failure

**Current state**: DestinationRule config present and correct; never
observed actually ejecting an endpoint, because no real load test in this
project ever generated a 5xx response.
**Risk**: low — the config is standard Istio syntax, but "configured
correctly" and "verified to work under real failure" are different
claims, and only the first is currently true here.
**Remediation**: combine Istio fault injection (configured to return
5xx) with simultaneous load generation in a dedicated test.

## 5. Falco real-time detection tested once, inconclusively

**Current state**: one live trigger (an anomalous shell command inside a
running pod) did not produce a matching log line in the checked window.
**Risk**: unknown whether this specific rule genuinely doesn't cover this
trigger type, or whether the test window/filter was simply wrong.
**Remediation**: retest with a broader log search window and a trigger
type known to match a specific, documented default Falco rule.

## 6. Single NAT Gateway (no AZ redundancy)

**Current state**: 1 NAT Gateway for the whole VPC (ADR-004).
**Risk**: single point of failure for all outbound internet access from
private subnets.
**Why it exists**: deliberate cost trade-off, stated openly.
**Remediation**: one NAT Gateway per AZ in a real production build.

## 7. Kyverno in `Audit`, not `Enforce`

**Current state**: policy violations are logged, not blocked.
**Risk**: a pod without resource limits is currently *allowed* to be
admitted (and this project has already been bitten by pod-scheduling
pressure once — PM-2).
**Remediation**: graduate to `Enforce` after a burn-in period once
confident the policy set doesn't produce false positives.

## 8. IAM access key rotation pending on `terraform-cli`

**Current state**: flagged in multiple sessions as needing rotation;
never actually completed.
**Risk**: standard credential-hygiene risk of a long-lived, unrotated
key.
**Remediation**: rotate, delete the old key, document the rotation date.

## 9. `kube-bench` check 3.2.7 (`--eventRecordQPS`) is permanently unfixable as configured

**Current state**: this kubelet flag is not configurable on EKS managed
node groups without a custom launch template/AMI.
**Risk**: low — this is a real, structural EKS limitation, not an
oversight.
**Remediation**: would require moving off managed node groups entirely; a
deliberate infra trade-off, not planned here.

## 10. Load-test latency numbers do not represent mesh overhead

**Current state**: `userservice` runs gunicorn's default single-worker
dev server, which serializes requests and dominates the measured latency.
**Risk**: none to the platform itself, but any reader taking the raw
p50/p99 numbers as "Istio's cost" would be misinformed.
**Remediation**: re-run the same load test against a multi-worker
gunicorn config to isolate actual sidecar overhead.

## 11. Phases 3, 4, and 5 of the original roadmap are not built

Chaos engineering/DR, GPU/AI infrastructure, and FinOps tooling are
explicitly out of scope for everything documented here. See README.md
"Future Work."

## Engineering Maturity — Plain Assessment

**Genuinely strong**: the CI/CD supply chain (real CVEs caught and fixed,
real signing, real policy gate), GitOps canary + automatic rollback
(proven by a real, unplanned failure, not staged), and the RBAC/
NetworkPolicy security testing (which found and fixed a real
misconfiguration rather than just checking that YAML existed).

**Production-shaped but not production-proven**: the observability stack
(Prometheus/Grafana fully verified; Loki/Tempo/OTel installed and
running but not yet exercised with real trace/log query workflows), Vault
(pattern proven, durability not).

**Weak / open**: image-signature admission enforcement, mTLS traffic-level
proof, circuit-breaker functional proof, Falco detection coverage for the
one trigger type tested. These are named explicitly rather than implied
to be solved.
