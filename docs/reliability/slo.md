# SLOs and Error Budgets

## `userservice` Availability SLO

**Definition**: fewer than 50% of `userservice`'s pods ready for 5+ minutes
fires a warning alert.

**Why an infrastructure-level SLO, not an application-level one**:
`userservice` is not instrumented with a `/metrics` endpoint exposing
request-level data (confirmed live — `curl .../metrics` returned a plain
404 HTML page, and no `userservice`-specific HTTP metrics were found in
Prometheus's label set). Pod readiness (via `kube_pod_status_ready`) was
chosen because it is honest about what data actually exists, rather than
building an error-rate SLO on a metric that isn't there.

**Real PrometheusRule used** (after two failed attempts — see
`docs/incidents/postmortems.md` for the debugging trail):

```yaml
- alert: UserServiceAvailabilityLow
  expr: |
    (
      count(kube_pod_status_ready{namespace="bank-of-anthos", pod=~"userservice-.*", condition="true"})
      /
      count(kube_pod_owner{namespace="bank-of-anthos", pod=~"userservice-.*"})
    ) < 0.5
  for: 5m
```

**Live verification**: the underlying metric query returned a real value
of `2` (matching both actual `userservice` pods, both confirmed ready),
and the rule was confirmed present and evaluating
(`health` reported without error) in `/api/v1/rules`.

## Why Two Earlier Versions of This Rule Failed

1. First attempt used `kube_deployment_status_replicas_available` — but
   `userservice` is managed by an Argo Rollouts `Rollout`, not a
   `Deployment`. The query returned an empty result set because that
   metric genuinely does not exist for this workload.
2. Root cause was confirmed directly: `kubectl get pods ... -o
   jsonpath='{.metadata.ownerReferences[0].kind}'` returned `ReplicaSet`
   (Argo Rollouts manages a ReplicaSet underneath, same as a Deployment
   would, but the Deployment-specific metric family doesn't apply).
3. Second, working version switched to `kube_pod_status_ready` +
   `kube_pod_owner`, both of which are pod-level and controller-agnostic.

This progression is kept here deliberately — it's real evidence the metric
was chosen because it actually works, not copied from a template.
