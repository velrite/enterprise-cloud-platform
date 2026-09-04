# Operations Runbook

## 0. Before Anything Else — the WSL2 DNS Check

This has broken the **start of nearly every session** on this project. Run
this proactively, every time, before touching Terraform/kubectl/AWS CLI:

```bash
cat /etc/resolv.conf
nslookup sts.us-east-1.amazonaws.com
```

If either command fails, is empty, or does not show
`nameserver 8.8.8.8` / `nameserver 1.1.1.1`, run (one command at a time,
not pasted as a block — heredocs have been observed to get mangled by
paste timing in this environment):

```bash
sudo tee /etc/wsl.conf > /dev/null <<'WSLEOF'
[network]
generateResolvConf = false
WSLEOF
sudo rm -f /etc/resolv.conf
echo "nameserver 8.8.8.8" | sudo tee /etc/resolv.conf
echo "nameserver 1.1.1.1" | sudo tee -a /etc/resolv.conf
sudo chattr +i /etc/resolv.conf
```

Then, from **Windows PowerShell** (not the Linux terminal): `wsl --shutdown`,
reopen the terminal, and re-run the two check commands until they pass
before doing anything else. This fix has been applied and lost again more
than once across sessions — do not assume it "stuck" from last time.

## 1. Rebuilding the Cluster From Zero

```bash
cd terraform/network && terraform apply -auto-approve
cd ../cluster && terraform apply -auto-approve
aws eks update-kubeconfig --region us-east-1 --name ecp-cluster
kubectl get nodes   # confirm ALL Ready before proceeding
```

Then reinstall, in this exact order — every step here exists because
getting the order wrong caused a real incident at some point in this
project:

1. Baseline namespaces / default-deny NetworkPolicy / RBAC
   (`k8s/baseline/`)
2. ArgoCD — **then explicitly verify**
   `kubectl get crd | grep -i applicationset` returns a result (PM-1: this
   CRD has been silently missing from a "successful" ArgoCD install before)
3. Argo Rollouts — verify `kubectl get crd rollouts.argoproj.io`
4. App-level secrets/ConfigMaps for `userservice` (JWT keypair remapped to
   `privatekey`/`publickey` filenames — see PM-4; `environment-config`;
   `accounts-db-config`; the `bank-of-anthos` ServiceAccount) — none of
   these survive a cluster rebuild and must be recreated every time
5. The ArgoCD `Application` pointing at `userservice`
6. Istio — use the exact resource-override command from ADR-005, not the
   plain default install
7. **VPC CNI NetworkPolicy enforcement** —
   `kubectl set env daemonset aws-node -n kube-system
   ENABLE_NETWORK_POLICY=true` — without this, the default-deny
   NetworkPolicy exists but does nothing (PM-9)
8. Vault, Kyverno, Falco (Helm installs)
9. **EBS CSI driver add-on** — install this *before* anything that needs a
   PVC (Loki, Tempo). Getting this order wrong is PM-3.
10. Prometheus/Grafana (`kube-prometheus-stack`)
11. Loki (`--set loki.useTestSchema=true` is required for the chart
    version in use, see PM-6b) → Tempo → OpenTelemetry Collector
    (`--set image.repository=otel/opentelemetry-collector-k8s` is
    required, and the `loki` exporter type has since been renamed
    `otlp_http` upstream — see PM-8)

## 2. Responding to a Falco Runtime Alert

1. Identify pod/namespace from the alert's `output_fields`.
2. `kubectl describe pod <pod> -n <ns>` — check events, image, correlate
   with ArgoCD sync history.
3. `kubectl logs <pod> -n <ns> --previous` if the pod restarted.
4. If confirmed malicious: `kubectl cordon <node>` then
   `kubectl delete pod <pod> -n <ns>`.
5. `kubectl get polr -A` — check whether a Kyverno policy should have
   blocked this and didn't (policy gap vs. genuine attack).
6. **Known limitation, be aware of it here**: this project's own live test
   of Falco (a real anomalous shell command inside `userservice`) did not
   produce a matching log line in the checked window. Do not assume Falco
   will fire on every trigger type without independently confirming the
   specific rule coverage for the alert you're chasing.

## 3. Responding to a Failed Compliance Check (kube-bench)

1. Re-run kube-bench to rule out a transient issue.
2. Identify the regressed check ID, diff against the documented
   before/after baseline.
3. Known cause on this project: a full cluster rebuild resets
   kubelet/API-server flags to EKS defaults, silently undoing any manual
   hardening Terraform never captured.
4. Reapply, re-verify, record the timestamp. **Known permanent limitation
   on this project**: check `3.2.7` (`--eventRecordQPS`) cannot be fixed at
   all on an EKS managed node group without a custom launch
   template/AMI — this is a real infra constraint, not something to keep
   re-debugging.

## 4. DaemonSet Pod Stuck `Pending`

1. Check `nodeAffinity` first:
   `kubectl get pod <pod> -n <ns> -o jsonpath='{.spec.affinity}'`.
2. Check that exact node's real pod count, not cluster-wide averages.
3. On `t3.small`, the real ceiling is 11 pods/node — an AWS ENI limit.
   Scaling the node group elsewhere does nothing if the *bound* node is
   full.
4. `kubectl cordon <node>` → `kubectl drain <node> --ignore-daemonsets
   --delete-emptydir-data --force` → wait for reschedule →
   `kubectl uncordon <node>`.

## 5. Storage-Bound Pods Stuck `Pending`

1. `kubectl get pvc -A` — look for `Pending`.
2. `kubectl get storageclass` — confirm a provisioner actually exists.
3. `kubectl describe pvc <name> -n <ns>` — look for
   `waiting for a volume to be created`.
4. Fix: see ADR-009 for the exact IAM role + add-on install commands.

## 6. Helm "Phantom" Failed Release Blocking Reinstall

Symptom: `Error: cannot re-use a name that is still in use`, but no real
pods exist. Cause: an earlier failed install (commonly a transient network
timeout) left a stale release record. Fix:
`helm uninstall <name> -n <namespace> --no-hooks`, check with
`helm list -n <namespace> -a` (the `-a` surfaces failed/pending releases
that plain `helm list` hides), then reinstall clean.

## 7. GitHub Pages CDN Connectivity (Helm Repo Adds Failing)

Symptom: `helm repo add`/`helm repo update` against
`*.github.io` chart repos (grafana, kyverno, falcosecurity,
prometheus-community, open-telemetry, argo) fails with
`connect: connection refused`, while `hashicorp` and `jetstack` (not
GitHub-Pages-hosted) succeed in the same run. This has been confirmed
**intermittent, not a hard block** — a retry loop
(`for i in 1 2 3; do helm repo update && break; sleep 5; done`) has
resolved it every time it was hit. Do not assume it is a permanent network
block; retry before escalating to a deeper network diagnosis.
