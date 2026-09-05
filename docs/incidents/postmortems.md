# Incident Postmortems

All incidents below occurred during development/operation of this lab
platform, not against real production traffic or real customers. Impact is
scoped accordingly — "impact" below means "blocked project progress," not
"caused a customer-facing outage."

---

### PM-1: ArgoCD ApplicationSet Controller Silent Crash Loop

**Detection**: `argocd-applicationset-controller` showed 880 accumulated
restarts, cycling roughly every 2 minutes.
**Root cause**: `kubectl logs <pod> --previous` (the `--previous` flag was
essential — the fresh restart's own logs were near-empty) revealed
`no matches for kind "ApplicationSet"` — the CRD itself was missing from
the cluster, likely dropped during a prior rebuild whose ArgoCD manifest
didn't include it.
**Resolution**: Applied the CRD directly
(`kubectl apply -f applicationset-crd.yaml --server-side --force-conflicts`),
deleted the pod to force immediate retry. Confirmed stable at 0 restarts.
**Prevention**: Rebuild runbook now explicitly verifies
`kubectl get crd | grep -i applicationset` after every ArgoCD install.

### PM-2: DaemonSet Pods Permanently Pending Despite Cluster-Wide Headroom

**Detection**: 2 of 9 `node-exporter` pods stuck `Pending` after
installing `kube-prometheus-stack`; scaling the node group further did
**not** fix it.
**Root cause**: DaemonSet pods bind via `nodeAffinity` to one specific
node at creation. The two stuck pods were bound to nodes already at
`t3.small`'s 11-pod ENI ceiling — an AWS networking limit, not a
Kubernetes setting, and not fixable by adding capacity elsewhere.
**Resolution**: Cordon + drain each full node one at a time, letting
existing pods reschedule elsewhere and freeing a slot, then uncordon. No
data loss — Vault (dev-mode, stateless-equivalent) and ArgoCD controllers
(stateless reconcilers) rescheduled cleanly.
**Prevention**: Check `nodeAffinity` and the bound node's real pod count
before reaching for node-group scaling as the first move.

### PM-3: Storage-Backed Pods Stuck Pending — Missing EBS CSI Driver

**Detection**: `tempo-0`, `loki-0`, and Loki's cache pods all `Pending`
simultaneously.
**Root cause**: EKS does not install the EBS CSI driver by default; it had
never been added to this cluster.
**Resolution**: Registered the OIDC thumbprint, created an IAM role
trusted by the driver's service account, attached
`AmazonEBSCSIDriverPolicy`, installed as an EKS managed add-on. PVCs
bound within minutes.
**Prevention**: Rebuild order now installs the EBS CSI add-on before any
PVC-backed workload (see runbook step 9).

### PM-4: `userservice` Pods CrashLooping — JWT Secret Key/Filename Mismatch

**Detection**: A fresh Rollout created 2 pods, both crashing immediately.
**Root cause**: The JWT secret's real key names
(`jwtRS256.key`/`jwtRS256.key.pub`) need an `items` remap in the volume
mount to the filenames the app actually expects on disk
(`privatekey`/`publickey`). This remap was dropped when the Rollout
manifest was rewritten from the original Deployment.
**Resolution**: Re-added the `items` remap block, validated with `grep`
before pushing, applied, forced an ArgoCD sync.
**Prevention**: Diff volume mounts specifically against the last
known-working manifest when rewriting from scratch — this class of drop
does not fail loudly at `kubectl apply` time, only at container start.

### PM-5: Secret-Scanner False-Positive Storm on a Fork

**Detection**: Gitleaks with `fetch-depth: 0` returned 60 "leaks."
**Root cause**: Years of dummy/demo credentials baked into Bank of
Anthos's own upstream manifests going back to 2019 — inherited history,
not anything this project wrote, and not live secrets.
**Resolution**: Scoped Gitleaks to `--no-git --source=<owned-path>` —
current files in the owned service folder only.
**Prevention**: Never rewrite upstream git history in a fork; audit what
you add, not an inherited project's entire history.

### PM-6a: `kubectl apply` Failing on Large CRDs (Annotation Size Limit)

**Detection**: Applying ArgoCD's ApplicationSet CRD via plain
`kubectl apply -f` failed outright.
**Root cause**: `kubectl apply` stores the full config in an annotation
for diffing; this specific CRD exceeds Kubernetes' 262KB annotation
limit.
**Resolution**: `kubectl apply -f <file> --server-side --force-conflicts`.

### PM-6b: Helm "Phantom" Failed Release Blocking Reinstall

**Detection**: `helm install` refused to proceed, citing an existing
release with no actual pods running.
**Root cause**: An earlier failed install (a transient DNS/network
timeout mid-install) left a stale release record in Helm's own tracking
state.
**Resolution**: `helm uninstall ... --no-hooks` to clear the stale record
first, then a clean install.
**Prevention**: Check `helm list -n <namespace> -a` before assuming a
clean slate.

### PM-6c: Loki Chart Requires an Explicit Schema Flag

**Detection**: `helm install loki ...` failed:
`You must provide a schema_config for Loki`.
**Root cause**: The installed chart version requires an explicit storage
schema; the chart's own error message names the exact fix for lab/testing
use.
**Resolution**: Added `--set loki.useTestSchema=true` to the install
command.

### PM-7: Terraform-Managed Nodegroup Rejects `t3.medium`

**Detection**: `terraform apply` on the node group failed:
`InvalidParameterCombination — The specified instance type is not
eligible for Free Tier`.
**Root cause**: This AWS account's Free Plan blocks non-Free-Tier
instance types at the API level, independent of credit balance.
**Resolution**: Reverted to `t3.small`, solved subsequent capacity issues
via horizontal scaling instead (see ADR-003, ADR-005 for the one
exception).

### PM-8: OpenTelemetry Collector CrashLooping / Pending — Multiple Causes

**Detection**: `otel-collector` DaemonSet pods showed a mix of `Pending`
and `CrashLoopBackOff`.
**Root cause, layered**: (1) the chart now requires an explicit
`image.repository` value — install failed outright without it; (2) once
that was fixed, remaining pod-count-ceiling pressure (same class of issue
as PM-2) caused some pods to stay `Pending` until the node group was
scaled; (3) the `loki` exporter type was renamed `otlp_http` upstream in
the chart version in use — the chart's deprecation notice auto-rewrote
this at install time, but it was worth confirming was not the crash
cause via `kubectl logs --previous` before assuming it was fixed.
**Resolution**: `--set image.repository=otel/opentelemetry-collector-k8s`,
node scaling, and confirming the exporter auto-rewrite via install output.

### PM-9: AWS VPC CNI Does Not Enforce NetworkPolicy by Default

**Detection**: A live security test (see
`docs/security/security-controls.md`, Round 1 Test 2) found a pod in an
unrelated namespace could reach `userservice` despite a default-deny
`NetworkPolicy` object existing in the cluster.
**Root cause**: AWS VPC CNI (`aws-node`) does not enforce
`NetworkPolicy` objects without an explicit opt-in — the policy existing
as a Kubernetes object is necessary but not sufficient.
**Resolution**: `kubectl set env daemonset aws-node -n kube-system
ENABLE_NETWORK_POLICY=true`, waited for rollout, **re-tested and
confirmed the fix**: the identical cross-namespace request that
previously leaked now failed with `Connection reset by peer`.
**Prevention**: Never assume a `NetworkPolicy` object being present means
it is being enforced on EKS — verify the CNI's actual enforcement
capability and configuration.

### PM-10: mTLS Traffic-Level Telemetry Not Present at Test Time

**Detection**: `count(istio_requests_total)` returned an empty result set
in Prometheus, even after a properly-waited port-forward.
**Root cause**: not fully diagnosed — the metric was simply absent from
Prometheus's scraped data at the time of testing. `PeerAuthentication:
STRICT` is independently confirmed present via `kubectl get`, but the
live-traffic evidence that would prove mTLS is actually being applied to
real requests was not obtainable in this session.
**Status**: open, documented in technical debt, not silently dropped.

### PM-11: Circuit Breaker / Outlier Detection Never Observed Firing

**Detection**: 50 rapid real requests against `userservice` all returned
`200`; no outlier-detection ejection stats appeared in the sidecar's stat
dump.
**Root cause**: no failure condition was ever actually created — Istio's
outlier detection requires real 5xx responses to trigger, and none
occurred during any load test run in this project.
**Status**: configuration confirmed present and correct; functional
behavior under real failure remains unverified. A real test would require
combining Istio fault injection (configured to return 5xx) with
simultaneous load generation — not attempted in this build.

### PM-12: Load-Testing Tooling Failures Before a Valid Result Was Obtained

**Detection**: (1) a `hey` binary download from a third-party S3 URL
returned an XML error page instead of the binary, causing bash to attempt
to execute XML as a script; (2) the first `ab` attempt raced a
`kubectl port-forward` that had not yet finished establishing, producing
a false `Connection refused` baseline.
**Resolution**: (1) switched to `apache2-utils` (`ab`) from Ubuntu's own
package repo, avoiding third-party binary downloads entirely; (2) waited
explicitly for `Forwarding from` in the port-forward's log before sending
any traffic.
**Prevention**: never trust a `sleep N` as proof a port-forward is ready
— poll the actual log output for confirmation.

### PM-13: WSL2 DNS Resolver Breaks Recurring Across Sessions

**Detection**: total DNS resolution failure at session start
(`172.18.240.1:53: server misbehaving`), blocking every AWS endpoint —
not GitHub-Pages-specific like PM-9's cousin issue, a complete resolver
failure.
**Root cause**: WSL2's auto-generated `/etc/resolv.conf` is unreliable in
this environment and has reset itself more than once even after being
"permanently" fixed and locked (`chattr +i`) in a prior session.
**Resolution**: `generateResolvConf = false` in `/etc/wsl.conf`, manually
set `/etc/resolv.conf` to public DNS (`8.8.8.8`, `1.1.1.1`), locked the
file, and required a `wsl --shutdown` from the Windows side for the
`wsl.conf` change to actually take effect.
**Prevention**: check this proactively at the start of every single
session (see runbook section 0) — do not wait for it to break again.

### PM-14: AWS Free Plan Exhaustion — Environment Change for Phase 3
**Date**: 2026-09-05
**Severity**: Medium (project-continuity impact, not a technical failure)
**Detection**: AWS sent an account notice that Free Plan credits were
fully consumed on account 681117450689, requiring a switch to standard
pay-as-you-go billing (a valid payment method) to continue provisioning
paid resources. No policy violation, no unpaid balance — a normal Free
Plan credit ceiling being reached.
**Root cause**: Phases 1–2 were built and repeatedly rebuilt live against
a real EKS cluster (t3.small nodes, NAT Gateway, EBS volumes,
load-balanced Istio ingress) across many working sessions. Real
infrastructure carries a real running cost; the starting credit was
consumed by legitimate, documented usage, not waste — see
`docs/operations/cost-analysis.md` for the Phase 1–2 spend breakdown.
**Resolution**: No further paid AWS resources are available for this
project at this time. Phase 3 (Resilience, Chaos Engineering & Disaster
Recovery) is built instead on GitHub Codespaces, running a local-style
Kubernetes cluster (`kind`) inside the Codespace container — zero
additional cloud cost, real multi-node Kubernetes, real
pod/network/disk chaos injection, real Patroni/Redis Sentinel/etcd
failover.
**What changes, explicitly**:
| Capability | Phase 1–2 (AWS/EKS) | Phase 3 (Codespaces/kind) |
|---|---|---|
| Compute | Real EC2 t3.small nodes | Docker containers acting as nodes, on GitHub's shared compute |
| Storage | EBS CSI driver, real PVs | `kind`'s local-path-provisioner |
| Networking | Real VPC, real AZs | Single-host Docker networking (no real AZ/region separation) |
| "Region failure" chaos test | Not attempted in Ph1/2 | Simulated as full node-group loss — explicitly a simulation, not a real multi-region test |
| Cost data | Real AWS Cost Explorer numbers | No real bill exists on Codespaces — Phase 5 will use Ph1/2's historical export instead |
**Prevention**:
1. Set an AWS Budget alert *before* the first dollar of credit is spent,
   not after — this was never done in Phase 1–2.
2. If AWS access is restored for a future phase, tear down (`terraform
   destroy` in `network`/`cluster`, never `bootstrap`) at the end of
   every session without exception, not "most" sessions.
3. Phase 5 (FinOps) will use Phase 1–2's real historical Cost Explorer
   export as its actual data source — Codespaces has no billing signal
   to analyze, so tooling (Kubecost/OpenCost) run there is a
   demonstration only, not the source of findings.

### PM-15: Default-Deny NetworkPolicy Blocked DNS, Breaking Istio Sidecar Certs
**Date**: 2026-09-05
**Detection**: `userservice` pods stuck at `1/2 Ready` indefinitely after
deploying to the Codespaces/kind cluster. `istio-proxy` sidecar logs
showed repeated `i/o timeout` errors resolving `istiod.istio-system.svc`
via CoreDNS (`10.96.0.10:53`), preventing the sidecar from obtaining its
workload certificate.
**Root cause**: The baseline `default-deny-all` NetworkPolicy
(`podSelector: {}`, `policyTypes: [Ingress, Egress]`) had zero egress
rules — a fully strict deny with no exceptions. This blocked ALL egress
including DNS lookups (port 53), which every pod needs even to resolve
in-cluster service names like `istiod.istio-system.svc`. Confirmed via
direct test: deleting the policy immediately restored DNS resolution and
pod readiness; re-adding a corrected version with an explicit DNS-allow
egress rule to `kube-system` on UDP/TCP 53 restored both readiness AND
re-confirmed cross-namespace traffic was still blocked (security posture
intact).
**Resolution**: Added an explicit `egress` rule to `default-deny-all`
permitting only DNS traffic (UDP/TCP 53) to the `kube-system` namespace,
leaving all other egress and all ingress denied by default.
**Prevention**: Any default-deny NetworkPolicy in a real environment
needs a paired DNS-allow rule from day one — this is a well-known but
easy-to-forget pairing. Test pod readiness immediately after applying
any new default-deny policy, not just security isolation, since a fully
strict deny breaks normal cluster operation (DNS, and by extension
Istio's control-plane cert issuance) just as effectively as it blocks
attackers.

### PM-16: Default-Deny NetworkPolicy Blocked Same-Namespace Peer Traffic, Breaking etcd Quorum
**Date**: 2026-09-05
**Detection**: A 3-node etcd StatefulSet reached `Running` status on all
pods, but `etcdctl endpoint health` and `member list` both timed out.
Pod logs showed repeated failed raft pre-vote rounds and `503`/`i/o
timeout` errors when nodes attempted to reach each other on peer port
2380 (e.g. `etcd-0` failing to reach `etcd-1.etcd:2380`).
**Root cause**: The `default-deny-all` NetworkPolicy (already patched
once for DNS in PM-15, and again for istio-system egress) still had no
rule allowing pods to reach OTHER PODS within the same `bank-of-anthos`
namespace. This is fine for a purely client-server app like `userservice`
(which only calls outward to DNS, the mesh control plane, and the DB),
but etcd's raft protocol requires direct peer-to-peer traffic between
its own members — same-namespace pod-to-pod communication that was never
explicitly allowed.
**Resolution**: Added a general same-namespace `ingress`/`egress` rule
(`podSelector: {}` with no namespace restriction) permitting any pod in
`bank-of-anthos` to reach any other pod in the same namespace, while
leaving all cross-namespace ingress/egress denied by default except the
existing DNS and istio-system exceptions. Re-verified cross-namespace
isolation was still intact after the change (a pod in `default` namespace
still could not reach `userservice`).
**Prevention**: A default-deny NetworkPolicy's required exceptions
depend entirely on the workload types sharing that namespace, not just
on the app you tested it against first. Any namespace that will host a
distributed/clustered system (etcd, Patroni, Redis Sentinel, Kafka,
etc.) needs a same-namespace peer-traffic allow rule from the start —
a policy that passed testing against a single stateless app is not
proof it will work for a peer-to-peer system added later. This is the
third NetworkPolicy-related gap found this session (PM-15: DNS,
istio-system; PM-16: same-namespace peers) — worth testing ALL
communication patterns a namespace will ever need, not just the first
workload deployed into it, before considering a default-deny policy
"done."
