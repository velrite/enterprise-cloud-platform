# Security Controls — Live Verification Log

This document is the real transcript-derived record of a deep-verification
pass run against the live cluster, in three rounds (initial pass, fixes,
re-verification). It exists so security claims in this repository trace
back to an actual command and its actual output, not an assumption.

## Round 1 — Initial Findings

**Test 1 — RBAC boundary**: A ServiceAccount bound only to a `view`
ClusterRole in `bank-of-anthos` was confirmed able to read secrets in its
own namespace and explicitly denied (`Forbidden`, real API error, not just
`can-i`) from reading secrets in `kube-system`. **Result: PASS, real
enforcement confirmed.**

**Test 2 — NetworkPolicy default-deny**: A pod in an unrelated namespace
successfully reached `userservice` on port 8080 despite the default-deny
policy existing. **Result: FAIL on first attempt — real gap found**, not a
config typo. Root cause identified in Round 2/3 below.

**Test 3 — Falco real-time detection**: An anomalous shell command was
executed live inside a `userservice` pod. No matching log line was found
in Falco's output for the following 60 seconds, filtered for
shell/spawn/pod-name keywords. **Result: inconclusive, documented as such
— not claimed as a pass.**

**Test 4 — PodDisruptionBudget under a real node drain**: First attempt
used a single port-forwarded pod as the traffic source; 16 of 30 requests
during the drain returned non-200 (`000`, connection errors) because the
port-forward itself was bound to a single pod that got evicted mid-test —
a **test methodology flaw**, not proof the PDB failed. Corrected in Round 2.

**Test 5 — Unsigned image admission check**: Searched all ClusterPolicies
for any signature-verification rule (`verifyImages`, `cosign`, `sigstore`)
— none found. **Result: confirmed real gap** — signature checking is
pipeline-only.

**Test 6 — mTLS real evidence**: Query attempted with invalid PromQL
syntax, fixed in Round 2/3; see below.

**Test 7 — Circuit breaker under real fault**: Load-generation command had
a syntax error (`curl` received no URL due to a `<()` process-substitution
mistake) on the first attempt; fixed in Round 2/3.

**Test 8 — SBOM real queryability**: `syft` installed locally, pointed at
the actual deployed image
(`ghcr.io/velrite/bank-of-anthos-userservice:2821d02c...`). Result: **1241
packages enumerated**, and a specific, real query (`flask` version) was
answered directly from the generated SBOM: `flask 3.1.3`. **Result: PASS,
genuinely queryable, not just an artifact that exists.**

## Round 2 — Fixes and Corrected Methodology

- **Test 2 re-confirmed via a second method**: `kubectl get networkpolicy`
  showed the policy object exists; `kubectl get daemonset -n kube-system`
  showed the CNI in use is AWS VPC CNI (`aws-node`), which is documented to
  **not** enforce NetworkPolicy without an explicit opt-in flag.
- **Test 4 corrected**: switched from a single pinned port-forwarded pod to
  a dedicated in-cluster traffic-generator pod hitting the real Service
  ClusterIP (the realistic client path) while draining a node hosting a
  `userservice` replica. Result: **39 of 40 requests succeeded** (`200`),
  1 `FAIL` at the very start of the run (before the drain began, not
  caused by it). This is real, strong evidence the PDB is protecting
  availability, once tested correctly.
- **Test 6 fixed query**: corrected PromQL syntax; result still empty —
  see Round 3.
- **Test 7 fixed load generator**: real 50-request burst sent via
  port-forward; all returned `200`. No outlier-detection stats appeared in
  the sidecar's stat dump for `userservice`, filtered for
  `outlier|ejections`.

## Round 3 — Root-Causing the NetworkPolicy Gap, Final Re-checks

- **Real fix applied**: `kubectl set env daemonset aws-node -n kube-system
  ENABLE_NETWORK_POLICY=true`, waited for the DaemonSet to roll.
- **Re-verified**: the exact same cross-namespace test that leaked in
  Round 1 now failed correctly: `wget: error getting response: Connection
  reset by peer`, non-zero exit code. **Confirmed fix working.**
- **Test 6, final attempt**: with a properly-waited port-forward, queried
  `count(istio_requests_total)` directly — result was an **empty vector**,
  meaning this metric was not present in Prometheus at all at test time,
  not merely filtered out by the label query. **Documented as inconclusive
  telemetry evidence for mTLS enforcement**, not a failure of mTLS itself
  (the `PeerAuthentication: STRICT` config is independently confirmed via
  `kubectl get`).
- **Test 7, final attempt**: same result as Round 2 — 50 real `200`
  responses, no outlier-detection stats observed. Documented as
  **unverified under real failure conditions**, since no 5xx responses
  were ever generated to actually trigger the ejection threshold.

## Honest Summary

Two controls were proven with hard, repeatable evidence: RBAC boundary
enforcement and NetworkPolicy default-deny (after a real, documented fix).
One control (PDB/zero-downtime drain) was proven strongly after correcting
a flawed first test. SBOM queryability was proven directly. Three areas —
Falco real-time detection, mTLS traffic-level telemetry, and
circuit-breaker firing — remain **configured but not confirmed by live
evidence**, and are listed plainly in
`docs/engineering/technical-debt.md` rather than claimed as working.
