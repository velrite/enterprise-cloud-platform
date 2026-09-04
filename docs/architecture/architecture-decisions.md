# Architecture Decision Records

## ADR-001: AWS over GCP

**Context**: Cloud provider had to be chosen before any infrastructure work.
**Problem**: The project's original spec explicitly requires IRSA (IAM
Roles for Service Accounts), which is AWS-specific with no direct GCP
equivalent (GCP uses Workload Identity, a different mechanism).
**Decision**: AWS.
**Alternatives rejected**: GCP — despite Bank of Anthos being a
Google-authored demo app, the IRSA requirement in the source spec decided
the platform, not the app's origin.
**Consequences**: All infra (Terraform, IAM, EKS) is AWS-native throughout.

## ADR-002: Fork Bank of Anthos rather than build a custom app

**Context**: The platform needed a real multi-service application to
generate genuine failure conditions.
**Decision**: Fork `GoogleCloudPlatform/bank-of-anthos` rather than write a
new demo app.
**Rationale**: A hello-world app cannot produce real mTLS-between-services,
traffic-splitting, or runtime-security scenarios — there's nothing to
split, encrypt, or watch. Multi-service, multi-language, real dependency
chains were needed.
**Consequences accepted**: Inherited upstream quirks — years of dummy
credentials in the app's own git history (see PM-5 in postmortems),
GCP-specific Cloud Trace wiring that had to be disabled for AWS (see PM in
incidents log), and the need to keep the fork's app code clearly separated
from platform code the author actually wrote.

## ADR-003: `t3.small` nodes

**Context**: AWS Free Plan on this account blocks `t3.medium` and larger
instance types outright (`InvalidParameterCombination`), confirmed
repeatedly, even with account credits available.
**Decision**: `t3.small` only.
**Consequences**: `t3.small` has an 11-pod-per-node ENI ceiling (an AWS
networking limit, not a memory/CPU limit) — this repeatedly caused
DaemonSet pods to get stuck `Pending` on already-full nodes even when
cluster-wide memory utilization was only 58-70%. Documented in PM-2.

## ADR-004: Single NAT Gateway (not one per AZ)

**Decision**: One NAT Gateway for the whole VPC.
**Rationale**: Real cost trade-off — a production-grade, fault-tolerant
setup would use one NAT Gateway per AZ, roughly doubling that specific
cost line.
**Consequence, stated plainly**: This is a single point of failure for
outbound internet access from private subnets. In the actual regulated-bank
scenario this project frames itself around, this would be a real finding
in an architecture review, not something to hide.

## ADR-005: Istio `profile=minimal` with explicit `istiod` resource overrides

**Context**: Default `istiod` requests 2Gi memory. `t3.small`'s allocatable
memory (~1.5GB) cannot satisfy that in a single pod, and this is **not**
fixable by adding more nodes — a single pod's request exceeding a single
node's capacity is unaffected by horizontal scaling.
**Decision**: `istioctl install --set profile=minimal --set
values.pilot.resources.requests.memory=512Mi --set
values.pilot.resources.requests.cpu=250m --set
values.pilot.resources.limits.memory=1Gi`.
**Verified working**: this exact command was reused successfully across at
least two full cluster rebuilds.
**Also noted**: Istio 1.30.3 explicitly states it does not support
Kubernetes 1.31 (minimum supported is 1.32) and prints a warning on every
install; it has continued to function in this environment, but this is a
live, acknowledged version mismatch, not a clean supported configuration.

## ADR-006: Vault in dev mode

**Decision**: `--set server.dev.enabled=true`, not production HA Vault.
**Rationale**: Sufficient to prove the secrets-management pattern on a lab
budget and inside session-length time constraints.
**Consequence, explicitly not hidden**: Not durable across pod restarts.
Real production-grade Vault (HA mode, real unseal ceremony, persistent
storage backend) is listed as Future Work.

## ADR-007: GHCR over ECR for the container registry

**Decision**: GitHub Container Registry.
**Rationale**: Authenticates automatically with the GitHub Actions token
already available in-workflow — zero additional OIDC federation setup.
**Alternative rejected**: ECR + AWS OIDC federation — a legitimate future
improvement (ties into the IRSA pattern already used for the EBS CSI
driver) but deliberately deferred as its own scoped task, not rushed in
alongside the initial pipeline build.

## ADR-008: Keyless Cosign signing over a static signing key

**Decision**: Keyless signing via GitHub OIDC (`cosign sign --yes`, no key
file).
**Rationale**: Avoids a real secret-management burden (protecting a static
private key); the resulting signature is verifiable back to "this exact
GitHub Actions run, in this exact repo."
**Real, documented gap**: This signature is currently verified during the
CI pipeline only. A live cluster test (`docs/security/security-controls.md`,
Test 5) confirmed no Kyverno or OPA policy on this cluster verifies image
signatures at admission time — an unsigned image is not currently blocked
from being scheduled if it somehow reached the cluster outside the
pipeline. Documented as a real, current limitation.

## ADR-009: EKS-managed EBS CSI add-on over a self-installed driver

**Context**: `tempo-0`, `loki-0`, and Loki's cache pods were discovered
stuck `Pending` — root cause was that EKS does not install the EBS CSI
driver by default, and it had never been added to this cluster (PM-3).
**Decision**: Registered the cluster's OIDC provider thumbprint, created an
IAM role trusted specifically by the `ebs-csi-controller-sa` service
account (IRSA pattern, same mechanism reason as ADR-001), attached
`AmazonEBSCSIDriverPolicy`, installed via `aws eks create-addon`.
**Alternative rejected**: Self-managed CSI driver via Helm — less
operational overhead choosing the managed add-on, at the cost of slightly
less control over driver version pinning.

## ADR-010: Kyverno in `Audit` mode, not `Enforce`

**Decision**: The `require-resource-limits` ClusterPolicy runs in
`validationFailureAction: Audit`.
**Rationale**: Logs and reports violations without blocking legitimate
work while the policy set is still small and unproven.
**Real evidence this is working as intended**: Falco's own pods were
observed triggering a real `PolicyViolation` event (missing resource
limits) that was correctly logged, not blocking Falco's actual
installation.
**Maturity path, stated explicitly**: A real production rollout would
graduate this policy to `Enforce` after a burn-in period — not done here,
noted as Future Work.
