# Screenshot Checklist

This documentation set was written from real command output and live test
results. The items below are the specific, real evidence points that are
strongest as visual screenshots for a portfolio review — capture these
against a live cluster, save into `docs/screenshots/`, named as listed.

| Filename | What to capture | Referenced in |
|---|---|---|
| `01-argocd-app-synced.png` | ArgoCD UI, `userservice` Application, `Synced`/`Healthy` | README.md, deployment.md |
| `02-github-actions-pipeline-green.png` | GitHub Actions run, all stages (scan/build/image-scan/sbom/sign/policy) green | supply-chain-security.md |
| `03-canary-rollout-progressing.png` | Terminal: `kubectl get rollout userservice -n bank-of-anthos` mid-canary | deployment.md |
| `04-automatic-rollback-event.png` | `kubectl describe rollout` or Argo Rollouts UI showing the real rollback event history | supply-chain-security.md |
| `05-kube-bench-before.png` | Full kube-bench summary table, before-hardening run | security-controls.md |
| `06-kube-bench-after.png` | Full kube-bench summary table, after-hardening run, same categories | security-controls.md |
| `07-grafana-dashboard-live.png` | Grafana, live node + pod metrics panel | system-overview.md |
| `08-prometheus-slo-rule-healthy.png` | Prometheus `/api/v1/rules` showing `UserServiceAvailabilityLow`, `health: ok` | slo.md |
| `09-rbac-boundary-denied.png` | Terminal: the real `Forbidden` error from the RBAC live test | security-controls.md |
| `10-networkpolicy-leak-then-fix.png` | Two-part: terminal showing the initial leak (`ok` response) and the fixed result (`Connection reset by peer`) | security-controls.md, PM-9 |
| `11-pdb-drain-results.png` | Terminal: the 39/40 traffic-generator results during the real node drain | failure-modes.md |
| `12-daemonset-pending-before-after.png` | `kubectl get pods -n monitoring -o wide` before and after the cordon/drain fix | postmortems.md PM-2 |
| `13-pvc-bound-after-ebs-csi.png` | `kubectl get pvc -A` showing all PVCs `Bound` after the EBS CSI fix | postmortems.md PM-3 |
| `14-sbom-real-query.png` | Terminal: the real `flask 3.1.3` query result against the live SBOM | security-controls.md, supply-chain-security.md |
| `15-load-test-full-output.png` | Full raw `ab` output table | failure-modes.md |
| `16-cost-real-numbers.png` | `aws eks describe-nodegroup` scaling config + node count table | cost-analysis.md |
| `17-istio-fault-injection-timing.png` | Terminal: the real ~5s (with fault) vs ~0.02s (without) curl timing comparison | (referenced in prior session work, mesh testing) |
| `18-wsl-dns-fix-confirmed.png` | Terminal: `nslookup` returning a real, fast resolution after the DNS fix | runbook.md section 0 |

Capture these once, against a stable live cluster, rather than
piecemeal across multiple rebuild sessions — several of the underlying
resources (nodes, pod names) change identity on every rebuild.
