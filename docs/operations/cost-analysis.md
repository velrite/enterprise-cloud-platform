# Cost Analysis

## Real Figures, Pulled Directly From the Live Account

- **EC2 (nodes)**: `t3.small` on-demand, ~$0.0208/hr each. Node count
  observed at different checkpoints ranged 2-9 depending on workload
  pressure; at a 9-node checkpoint this is ~$0.19/hr, ~$135/month if left
  running continuously.
- **NAT Gateway**: 1, ~$0.045/hr base charge plus data processing, ~$32/mo
  base alone before transfer costs.
- **EBS volumes**: Loki/Tempo PVCs (5Gi each) — a few dollars/month,
  negligible next to compute/NAT.
- **EKS control plane**: flat ~$0.10/hr regardless of cluster size.

## Where the Money Actually Goes, Ranked

1. **Node count** is the largest driver, and the real cause of landing at
   9 rather than a planned 5-7 was **not** manual over-provisioning — it
   was DaemonSet scheduling pressure and pod eviction during cordon/drain
   operations triggering organic scale-out beyond the last explicit
   `desiredSize`. This is a real, observed operational behavior worth
   knowing, not a mistake to hide.
2. **NAT Gateway** is a fixed cost regardless of cluster size — pure waste
   during idle hours on a lab cluster. A production mitigation would be an
   interface VPC endpoint for AWS API traffic (ECR/S3/STS) instead of
   routing everything through NAT. Not implemented here.
3. **Storage** is the smallest line item by far at this scale.

## Real Constraint Worth Naming in Any Cost Discussion

`t3.small`'s 11-pod-per-node ENI ceiling means additional nodes are
sometimes needed purely to satisfy pod-count scheduling, not actual
CPU/memory pressure — this cluster measured 58-70% memory utilization even
while pods failed to schedule elsewhere. Cheaper per-node, but the real
cost shows up in needing more nodes for equivalent pod capacity versus a
single larger instance (which this account's Free Plan restriction blocks
anyway — see ADR-003).

## What This Analysis Deliberately Does Not Cover

Managed alternatives (Fargate profiles, App Runner) that would eliminate
node management entirely are out of scope — this build was explicitly
about demonstrating self-managed EKS operational skill. A dedicated
FinOps tooling layer (Kubecost/OpenCost, automated waste detection,
forecasting) was planned in the original roadmap as "Phase 5" and was
**not built** — this document is a manual substitute using raw AWS CLI
output, not a mature cost-intelligence platform.
