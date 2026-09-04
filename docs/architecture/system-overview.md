# System Overview

## Purpose

Operate a forked copy of Google's Bank of Anthos as though it were a real,
regulated mid-size digital bank's payment service, with a full secure
software supply chain and observability stack wrapped around it.

## Components and Responsibilities

| Component | Responsibility | Namespace |
|---|---|---|
| EKS control plane | Kubernetes API, scheduling | managed by AWS |
| Managed node group (t3.small) | Compute, scaled 2→9 nodes across sessions depending on workload pressure | n/a |
| ArgoCD | GitOps reconciliation — cluster state matches the manifests in `bank-of-anthos` repo | `argocd` |
| Argo Rollouts | Canary rollout controller for `userservice`, replaces plain Deployment | `argo-rollouts` (controller), `bank-of-anthos` (workload) |
| Istio (`istiod`, sidecars) | mTLS, traffic policy, fault injection between in-mesh services | `istio-system` + sidecar-injected into `bank-of-anthos` |
| Vault (dev mode) | Secrets management pattern, not durable | `vault` |
| Kyverno | Admission-time policy checks (Audit mode) | `kyverno` |
| Falco | Runtime anomaly detection via eBPF | `falco` |
| Prometheus / Grafana | Metrics collection and dashboards | `monitoring` |
| Loki | Log aggregation | `monitoring` |
| Tempo | Distributed tracing backend | `monitoring` |
| OpenTelemetry Collector | Unified logs/traces pipeline into Loki/Tempo | `monitoring` |
| `userservice` (Bank of Anthos) | The one workload actually deployed and load-tested in this build | `bank-of-anthos` |

## Control Plane vs Data Plane

- **Control plane**: ArgoCD (deploy decisions), Kyverno (admission decisions),
  the EKS API server itself.
- **Data plane**: Istio sidecars carrying actual service-to-service traffic,
  `userservice` pods serving real HTTP requests.

## Real, Current Infrastructure Snapshot

Pulled directly from the live account during the most recent working
session — not estimated:

- EKS cluster: `ecp-cluster`, status `ACTIVE`, Kubernetes v1.31
- Node instance type: `t3.small` (AWS Free Tier plan restriction — larger
  types are blocked outright by the account, see ADR-003)
- Node count observed across sessions: ranged from 2 (fresh cluster) up to
  9 (after DaemonSet scheduling pressure and cordon/drain operations)
- NAT Gateways: 1, `available`
- Region: `us-east-1`

## Networking Reality Check (Important, Verified Live)

The cluster's default-deny `NetworkPolicy` existed as a Kubernetes object
from early in the project, but **AWS VPC CNI does not enforce
NetworkPolicy by default**. A live test confirmed a pod in an unrelated
namespace could successfully reach `userservice` despite the policy
existing (see `docs/incidents/postmortems.md`, PM-9). The real fix —
`kubectl set env daemonset aws-node -n kube-system ENABLE_NETWORK_POLICY=true`
— was applied and **re-verified**: the same cross-namespace request then
failed with `Connection reset by peer`. This is documented as a genuine,
lived finding, not a design assumption.

## App-Level Note

Only `userservice` from the full Bank of Anthos application was deployed
and exercised throughout this build. The rest of the Bank of Anthos
services (frontend, ledger-writer, balance-reader, transaction-history,
contacts) were never deployed in this environment — treat any reference to
"the app" in this documentation set as referring specifically to
`userservice`.
