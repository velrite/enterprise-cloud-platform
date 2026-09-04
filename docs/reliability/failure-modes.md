# Failure Mode Analysis

## Zero-Downtime Deploy / Node Drain (Real Test, Two Attempts)

**First attempt (flawed methodology)**: traffic sent via a single
`kubectl port-forward` bound to one specific pod. When that exact pod was
evicted during the drain, the port-forward itself died, producing 16 of 30
non-200 responses. **This measured the test harness breaking, not the
service.**

**Second attempt (corrected)**: a dedicated in-cluster pod sent 40 requests
over time against the real Kubernetes Service ClusterIP (the path any real
client actually uses) while a node hosting a `userservice` replica was
drained with `kubectl drain --ignore-daemonsets --delete-emptydir-data`,
protected by a `PodDisruptionBudget` (`minAvailable: 1`). **Result: 39 of
40 requests returned `200`.** The single `FAIL` occurred before the drain
even began, consistent with normal pod startup timing, not the drain
itself. This is real, credible evidence that the PDB is doing its job.

## DaemonSet Pods Stuck `Pending` Despite Cluster-Wide Headroom

Hit twice. Root cause both times: a DaemonSet pod is bound via
`nodeAffinity` to one **specific** node at creation — scaling the node
group elsewhere does nothing if that exact node is already full.
`t3.small`'s real ceiling is an AWS ENI-based 11-pods-per-node limit, not
memory or CPU (nodes were observed at 58-70% memory utilization while
still failing to schedule). Fix: `kubectl cordon` → `kubectl drain
--ignore-daemonsets --delete-emptydir-data --force` on the specific full
node → wait for reschedule → `kubectl uncordon`.

## Storage-Backed Pods Stuck `Pending`

`tempo-0`, `loki-0`, and Loki's cache StatefulSet pods were all `Pending`
simultaneously. Root cause: EKS does not install the EBS CSI driver by
default, and it had never been added to this cluster — confirmed via
`kubectl get storageclass` (a provisioner existed in name but nothing was
actually backing PVC creation) and `kubectl describe pvc` (`waiting for a
volume to be created`). Fixed via IRSA-trusted IAM role + EKS managed
add-on (ADR-009).

## Circuit Breaker / Outlier Detection — Untested Under Real Failure

Configured (`consecutive5xxErrors: 3`, `baseEjectionTime: 30s`,
`maxEjectionPercent: 50`) but never observed actually firing, because
every real load test against `userservice`'s `/ready` endpoint returned
`200` consistently — no 5xx responses were ever generated to trigger
ejection. This is a genuine gap in evidence, not a claim the feature
doesn't work; a real test would require injecting failures (e.g. via
Istio fault injection configured to return 5xx) while simultaneously load
testing, which was not done in this build.

## Load Test Result and Honest Interpretation

**Tool**: ApacheBench, 200 requests / 20 concurrent, against
`userservice`'s `/ready` endpoint through the real Istio-mesh path.

| Metric | Value |
|---|---|
| Complete requests | 200 |
| Failed requests | **0** |
| Requests/sec (mean) | 0.98 |
| Median latency (p50) | 20,040 ms |
| p95 latency | 21,584 ms |
| p99 latency | 22,143 ms |

**Honest interpretation**: zero failed requests is real, good evidence of
reliability under load. The ~20-second median latency is **not**
representative of Istio sidecar overhead (normally single-digit
milliseconds) — the `ab` output's `Server Software: gunicorn` line
reveals the actual bottleneck: `userservice` runs gunicorn's default
single-worker development server, which serializes concurrent requests.
Reporting this number as "mesh overhead" would misattribute the cause.
**Conclusion: mesh reliability proven; mesh performance overhead was not
measurable from this test, because the application layer was the actual
bottleneck.**

Two load-testing tool failures happened before this result was obtained:
a broken third-party `hey` binary download (stale S3 URL returning an XML
error page instead of the binary) and a port-forward race condition on
the first `ab` attempt (fired before the tunnel was confirmed established,
producing a false `Connection refused`). Both are documented in
`docs/incidents/postmortems.md`.
