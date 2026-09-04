# Infrastructure

## Terraform Layout

Three separate state stacks, deliberately isolated by blast radius and
change frequency:

1. **`terraform/bootstrap`** — S3 bucket + DynamoDB lock table for Terraform
   remote state itself. **Never destroyed**, touched once, ever.
2. **`terraform/network`** — VPC, 2 AZ public/private subnets, Internet
   Gateway, 1 NAT Gateway (see ADR-004).
3. **`terraform/cluster`** — EKS control plane + managed node group.

**Rebuild order**: `network` → `cluster`.
**Teardown order**: `cluster` → `network` (nodes live inside the VPC's
subnets; the VPC cannot be destroyed while they exist). `bootstrap` is never
torn down.

## EKS Cluster

- Kubernetes version 1.31 (managed control plane, AWS-operated)
- Node group: `t3.small`, scaling config adjusted repeatedly through the
  project as workloads were added — real config observed at one checkpoint:
  `minSize=1, maxSize=7, desiredSize=5`, which organically grew to 9 nodes
  under DaemonSet scheduling pressure (see PM-2).
- `endpoint_public_access = true` — chosen so `kubectl` works directly from
  the operator's laptop without a bastion/VPN. Documented trade-off: a
  stricter setup would set this `false` and require a bastion; deferred to
  Future Work, not forgotten.

## Free Plan Constraint (Real, Hit Repeatedly)

This AWS account is on a 6-month Free Plan (~$34 in credits remaining at
last check). This plan has a **hard restriction blocking non-Free-Tier
instance types** — `t3.medium` and larger fail outright with
`InvalidParameterCombination`, independent of credit balance. Confirmed
multiple times. All capacity problems on this project were solved via
**horizontal** scaling (more `t3.small` nodes) except the Istio `istiod`
memory case, which needed a **smaller footprint**, not more nodes, because
a single pod's memory request exceeded a single node's total capacity.

## Kubernetes-Level State Not Tracked by Terraform

Terraform only tracks the VPC and the EKS cluster/node group. Everything
installed via `helm install` or raw `kubectl apply` — ArgoCD, Argo
Rollouts, Vault, Kyverno, Falco, the observability stack, and all
app-level Secrets/ConfigMaps for `userservice` — is **not** tracked by
Terraform and is lost on every cluster rebuild. The rebuild runbook in
`docs/operations/runbook.md` documents the exact reinstall order this
project settled on after multiple sessions of getting it wrong.

## Real Cost Snapshot

See `docs/operations/cost-analysis.md` for the full breakdown with real
AWS CLI output.
