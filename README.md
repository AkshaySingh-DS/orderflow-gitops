# OrderFlow GitOps Repository

This repository is the deployment source of truth for OrderFlow.

The application repository (`orderflow-app`) owns Python source, tests, Dockerfile and CI. This repository owns Helm deployment configuration and the image version that should run in Kubernetes.

Argo CD will be connected to this repository in Phase 6. Until then, this repository can be validated independently with Helm.

## Repository layout

```text
orderflow-gitops/
├── .github/
│   └── workflows/
│       └── validate.yml
├── helm/
│   └── orderflow/
│       ├── Chart.yaml
│       ├── values.yaml
│       ├── values-dev.yaml
│       └── templates/
│           ├── _helpers.tpl
│           ├── configmap.yaml
│           ├── deployment.yaml
│           ├── hpa.yaml
│           ├── ingress.yaml
│           ├── migration-job.yaml
│           ├── service.yaml
│           └── serviceaccount.yaml
└── README.md
```

## Deployment ownership model

```text
orderflow-app
    |
    | build / test / scan
    v
ECR
    |
    | verified image
    v
orderflow-gitops
    |
    | Helm values
    v
Argo CD  (Phase 6)
    |
    v
K3s / Kubernetes  (Phase 6)
```

## Image promotion

The application CI creates a pull request that changes:

```text
helm/orderflow/values-dev.yaml
```

Specifically:

```yaml
image:
  repository: <ECR registry>/orderflow-api
  tag: sha-<git-sha>
```

Do not use `latest` for deployment.

## GitOps repository protection

Protect `main` with a pull request policy. Recommended checks:

```text
GitOps / Helm validation
```

Require the status check before merge and disallow force-pushes to `main`.

## Secrets

Database credentials are deliberately **not stored in this repository**.

The chart references an existing Kubernetes Secret:

```text
orderflow-db
  DATABASE_URL
```

Creation/rotation of that Secret will be handled as part of the Kubernetes deployment phase. Later, the project can move secret material to AWS Secrets Manager.

## Local validation

Install a supported Helm client for this project (the CI validation uses Helm v4.3.0, matching current Argo CD Helm rendering) and run:

```bash
helm lint helm/orderflow \
  -f helm/orderflow/values-dev.yaml \
  --strict

helm template orderflow helm/orderflow \
  -f helm/orderflow/values-dev.yaml \
  > /tmp/orderflow-rendered.yaml
```

The GitHub workflow performs the same validation on every pull request and push to `main`.

NOTE: IN helm configuration, values.yaml file is teh configuration which is common in across the environments, so this is overriden by the any other env values yaml file in helm. Best practice we keep the commn values irrespective of env in values.yaml






====
I would break Phase 6 into these checkpoints

| Checkpoint    | What must work |
|---|---|
| **A** | EC2 + IAM + Security Group |
| **B** | K3s node `Ready` |
| **C** | Argo CD installed and healthy |
| **D** | Argo CD can read `orderflow-gitops` |
| **E** | PostgreSQL secret + storage |
| **F** | ECR authentication works |
| **G** | Argo CD Application = `Synced/Healthy` |
| **H** | OrderFlow `/health` and `/ready` work |
| **I** | GitOps promotion causes a real Kubernetes rollout |

## Official documentation used:

[K3s Quick Start and installation](https://docs.k3s.io/quick-start?utm_source=chatgpt.com)
[K3s v1.36.5+k3s1 release: GitHub](https://github.com/k3s-io/k3s/releases?ref=blog.elest.io&utm_source=chatgpt.com)
[Argo CD v3.5.3 release/install](https://github.com/argoproj/argo-cd/releases?utm_source=chatgpt.com)
[Argo CD GitHub App/private repository access: Argo CD](https://argo-cd.readthedocs.io/en/release-3.1/user-guide/private-repositories/?utm_source=chatgpt.com)

[AWS EC2 IAM roles/instance profiles: AWS Documentation](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/iam-roles-for-amazon-ec2.html?utm_source=chatgpt.com)
[AWS ECR pull-only policy/authentication: AWS Documentation](https://docs.aws.amazon.com/aws-managed-policy/latest/reference/AmazonEC2ContainerRegistryPullOnly.html?utm_source=chatgpt.com)
[Kubernetes private-registry imagePullSecrets: Kubernetes](https://kubernetes.io/docs/tasks/configure-pod-container/pull-image-private-registry/?utm_source=chatgpt.com)
[AWS EC2 security groups](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/security-group-rules-reference.html?utm_source=chatgpt.com)


# OrderFlow Platform Configuration — Phase 7 Observability

This repository owns **platform-level desired state** for the OrderFlow portfolio: Argo CD projects/applications, and the Prometheus/Grafana/Loki/Alloy configuration. Application code stays in `orderflow-app`; the OrderFlow Helm chart stays in `orderflow-gitops`.

> **Scope and honesty:** This is a production-minded *portfolio deployment*, not an HA production service. It runs on one K3s node and uses `local-path` persistent volumes. A node, EC2, disk, or AZ outage can take out the API and observability data together. The configuration adopts production practices (GitOps, pinned chart versions, no committed credentials, private metrics path, retention, alert rules, dashboards, resource sizing), but does not provide multi-node availability, managed object storage, off-cluster retention, or alert delivery until those are deliberately added.

## Architecture

```text
orderflow-app
  └─ GitHub Actions: lint → test/coverage → security gates → Docker build → Trivy → ECR push
       └─ opens a PR updating the immutable image reference in orderflow-gitops

orderflow-gitops
  └─ Helm chart: Deployment, ClusterIP Service, Ingress, ServiceMonitor, metrics-only internal Ingress

orderflow-platform-config (this repo)
  └─ Argo CD declarative Applications + AppProject
      ├─ kube-prometheus-stack → Prometheus + Alertmanager + Grafana + node-exporter + kube-state-metrics
      ├─ Loki (monolithic, filesystem PVC, 7-day retention)
      ├─ Grafana Alloy → Kubernetes container logs → Loki
      ├─ OrderFlow PrometheusRule alerts
      └─ OrderFlow Grafana dashboard (ConfigMap sidecar provisioning)
```

## Why these components

- **kube-prometheus-stack** installs the Prometheus Operator, Prometheus, Alertmanager, Grafana, kube-state-metrics and node-exporter with useful standard dashboards and alert rules.
- **Grafana Alloy**, not Promtail: Promtail reached end of life on 2026-03-02. Alloy is configured to tail pod logs through the Kubernetes API, which avoids privileged host filesystem mounts in this small cluster. The API-based collector is operationally simpler, but adds Kubernetes API/kubelet traffic; a multi-node production fleet should evaluate a per-node DaemonSet/file-tail design and persist its positions.
- **Loki Monolithic** fits the resource/cost profile of a one-node portfolio and is the current recommended Loki mode for small meta-monitoring setups. Simple Scalable mode is deprecated. For a real multi-node production service, use external object storage such as S3 and evaluate Loki's distributed mode.
- **Persistent local-path volumes** preserve data across a pod restart, but not across loss of the EC2 host/volume. The instance disk and PVC capacity must be sized and monitored.
- **ServiceMonitor** uses the Prometheus Operator CRD to discover the OrderFlow Service; this is preferable to hand-maintained static scrape targets.
- **Grafana** remains ClusterIP-only. Access it via `kubectl port-forward`, not a public Ingress or open security-group port.

## Pinned chart versions

Versions are intentionally pinned in the Argo CD `Application` resources. Upgrade them through a reviewed Git PR, checking each chart's changelog and rendered manifests:

| Component | Chart | Pinned chart version |
|---|---|---:|
| Prometheus stack | `prometheus-community/kube-prometheus-stack` | `91.9.0` |
| Loki | `grafana-community/loki` | `18.5.0` |
| Alloy | `grafana/alloy` | `1.6.1` |

These are pinned chart versions verified against published chart releases during preparation (Prometheus stack 91.9.0; Loki 18.5.0; Alloy 1.6.1). They are not floating `latest` references. Check the chart repository again before applying because new versions may be released. The included `.github/workflows/validate-observability.yml` lints and renders all three pinned charts and builds the Kustomize bootstrap on pull requests. Review upgrades through a PR. Run Kubernetes API/schema conformance checks against the target cluster as an additional release check before promoting chart updates.

Release references: [kube-prometheus-stack](https://artifacthub.io/packages/helm/prometheus-community/kube-prometheus-stack/91.9.0), [Loki](https://artifacthub.io/packages/helm/grafana-community/loki), [Alloy](https://artifacthub.io/packages/helm/grafana/alloy/1.6.1).

## Before you start

1. K3s and Argo CD are installed and healthy.
2. A private `orderflow-platform-config` GitHub repository exists. Push this repository's contents there. Replace every `REPLACE_WITH_GITHUB_OWNER` placeholder with the real GitHub owner.
3. Argo CD can read the platform repository. Use a dedicated read-only GitHub App with **Contents: read** on this repo. The App installation used for `orderflow-gitops` must explicitly include `orderflow-platform-config`; access to the first repository does not automatically grant access to the second.
4. The K3s node has enough capacity. For this bundled observability stack, budget approximately **2 vCPU and 8 GiB RAM as a practical starting point**, plus disk space. This is a sizing starting point, not a guarantee; check actual requests and memory after installation. Do not expect this stack and all app workloads to fit comfortably on a tiny 1–2 GiB VM.
5. Size the EC2 root EBS volume for at least **40 GiB** (50 GiB gives more breathing room). The requested PVC sizes total about 26 GiB across Prometheus, Alertmanager, Grafana, Loki and PostgreSQL, before operating-system files, container images, logs and free-space headroom. K3s `local-path` stores these data directories on the node disk; these are not independent managed storage volumes.
6. K3s default StorageClass `local-path` is available: `kubectl get storageclass`.
7. Traefik is the ingress controller (the standard K3s installation includes it unless you disabled it).

## Configure Argo CD repository access

Set environment variables in your local shell; never put the private key in Git:

```bash
export GITHUB_OWNER='<your-github-owner>'
export GITHUB_APP_ID='<numeric-app-id>'
export GITHUB_APP_INSTALLATION_ID='<installation-id>'
export GITHUB_APP_PRIVATE_KEY_FILE="$HOME/.github/orderflow-platform-reader.pem"
```

The GitHub App needs read-only **Contents** permission on `orderflow-platform-config`. From the root of the checked-out platform-config repo:

```bash
bash bootstrap/register-platform-repo.sh
```

The script registers an Argo CD repository Secret and applies `bootstrap/root-application.yaml`. It does not modify your existing OrderFlow Application. If your Argo CD bootstrap already tracks this repository, keep your existing root Application rather than creating a duplicate.

## Bootstrap in the correct order

### 1. Create the monitoring namespace and Grafana admin secret

Do not store the Grafana password in a Helm values file. Generate it locally and create a Kubernetes Secret before the Prometheus stack first syncs:

```bash
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
read -rsp 'Grafana admin password: ' GRAFANA_ADMIN_PASSWORD; echo
kubectl -n monitoring create secret generic grafana-admin-credentials \
  --from-literal=admin-user=admin \
  --from-literal=admin-password="$GRAFANA_ADMIN_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -
unset GRAFANA_ADMIN_PASSWORD
```

The values reference `grafana-admin-credentials` keys `admin-user` and `admin-password`. Do not commit this Secret. For a larger environment, use External Secrets/AWS Secrets Manager or another controlled secrets workflow.

### 2. Install the three base components through Argo CD

The initial `clusters/k3s-dev/kustomization.yaml` intentionally contains only the base applications: kube-prometheus-stack, Loki, and Alloy. This avoids racing `PrometheusRule` and `ServiceMonitor` resources before the operator has installed its CRDs.

After pushing the repo and applying the root Application, check:

```bash
kubectl -n argocd get applications
kubectl -n monitoring get pods
kubectl -n monitoring get pvc
kubectl get crd servicemonitors.monitoring.coreos.com prometheusrules.monitoring.coreos.com
```

Wait for the Prometheus, Grafana, Loki and Alloy pods to become Ready and the CRDs to exist. If an App is OutOfSync/Degraded, use `kubectl -n argocd describe application <app>` and its controller logs before proceeding.

### 3. Add the alert rules and dashboard applications

After step 2 is healthy, edit `clusters/k3s-dev/kustomization.yaml` and uncomment these two resources:

```yaml
  - apps/orderflow-alerts.yaml
  - apps/orderflow-dashboard.yaml
```

Commit and push. Argo CD will apply the `PrometheusRule` CR in the `monitoring` namespace and the Grafana dashboard ConfigMap. The stack's Grafana dashboard sidecar watches ConfigMaps with label `grafana_dashboard: "1"`.

### 4. Add application metrics support

In `orderflow-app`, merge the Phase 7 changes:

- Add the pinned `prometheus-fastapi-instrumentator==8.1.0` runtime dependency.
- Expose `/metrics` in Prometheus text format, outside the OpenAPI schema.
- Test the endpoint in pytest.
- Let the existing CI pipeline test, scan, build and publish the resulting immutable image to ECR.

The app change must pass the existing security gates; do not bypass Trivy to get metrics deployed.

### 5. Update `orderflow-gitops`

Merge the Phase 7 Helm changes into `orderflow-gitops`. They add the `ServiceMonitor` and protect `/metrics` with a higher-priority Traefik route plus `ipAllowList`. The environment values enable both features and label the ServiceMonitor with `release: kube-prometheus-stack`, matching the Prometheus release selector.

Check the node PodCIDR first:

```bash
kubectl get nodes -o jsonpath='{.items[0].spec.podCIDR}{"\n"}'
```

The supplied default allow-list is `10.42.0.0/16`, the standard K3s pod CIDR. If the actual PodCIDR differs, update `metrics.internalIngress.allowedCIDRs` in `helm/orderflow/values-dev.yaml` before merging. This route assumes Prometheus reaches the Service from its pod IP. Validate the observed source address in your cluster; do not blindly broaden the range to `0.0.0.0/0`.

### 6. Validate the end-to-end signal path

```bash
kubectl -n orderflow get pods,svc,ingress
kubectl -n orderflow get servicemonitor
kubectl -n monitoring get prometheus,prometheusrule
kubectl -n monitoring get pods
```

Generate API traffic through the public OrderFlow endpoint, including one safe invalid request to produce a 4xx. Check the target in Prometheus's **Status → Targets** page: the `orderflow` target should be `UP`. Verify these metrics exist in Prometheus/Grafana:

- `http_requests_total`
- `http_request_duration_seconds_bucket`
- `container_cpu_usage_seconds_total`
- `container_memory_working_set_bytes`
- `kube_pod_container_status_restarts_total`

The `ServiceMonitor` label `jobLabel: app.kubernetes.io/name` causes the Prometheus job label to be `orderflow`. If the target shows another job name, inspect the rendered ServiceMonitor and adjust the alert/dashboard queries consistently.

## Secure Grafana access

Grafana, Prometheus, Alertmanager and Loki have no public Ingress in this setup. For local administration use port-forwarding:

```bash
kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80
```

Open <http://127.0.0.1:3000> and sign in with username `admin` and the password created above. Stop the port-forward when you are finished. Do not expose port 3000 or Prometheus 9090 in the EC2 security group. Prefer SSO/OAuth and TLS when making Grafana accessible to a team.

Prometheus UI (debug-only):

```bash
kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090
```

Loki is only used internally through its ClusterIP gateway. Alloy sends logs to:
`http://loki-gateway.monitoring.svc.cluster.local/loki/api/v1/push`.

## Dashboards

The `OrderFlow — Service Overview` dashboard provides:

- request rate;
- 5xx response ratio;
- p95 request latency;
- request rate by status code class;
- CPU and working-set memory by pod;
- container restart counters;
- recent OrderFlow container logs from Loki.

It uses the standard Prometheus and provisioned Loki data source UIDs. A zero/blank chart does not always mean an error: low-traffic histogram quantiles need enough samples, and metrics begin appearing after requests have been handled.

## Alerting

The stack's built-in Kubernetes rules remain enabled. The custom `PrometheusRule` adds:

| Alert | Condition | Hold period |
|---|---|---|
| `OrderFlowTargetMissing` | Prometheus cannot scrape the OrderFlow endpoint | 2 minutes |
| `OrderFlowHigh5xxRate` | 5xx rate exceeds 5% with meaningful request volume | 10 minutes |
| `OrderFlowHighP95Latency` | p95 HTTP duration exceeds 500 ms with meaningful request volume | 10 minutes |

Alerts are visible in Prometheus/Alertmanager. **External notifications are not configured** in this portfolio bootstrap, so do not claim Slack/email paging works. For production, configure an Alertmanager receiver through a Kubernetes Secret or a managed secrets system and test notification delivery.

## Logs and safe label cardinality

Alloy discovers pod targets via the Kubernetes API and applies stable labels: `cluster`, `environment`, `namespace`, `pod`, `container`, and `app`. It deliberately does not label by request ID, customer ID, order ID or raw URL. These values would create high cardinality and could also leak business data. Avoid logging tokens, database URLs, payment details or request bodies containing sensitive data.

Promtail is not used: it reached end of life on 2026-03-02 and Grafana directs users to Alloy for ongoing log collection.

## Resource and retention policy

- Prometheus retention: 7 days and at most 6 GB, with an 8 GiB PVC.
- Loki retention: 7 days with a 10 GiB PVC and retention compaction enabled.
- Grafana: 2 GiB PVC.
- Alertmanager: 1 GiB PVC.
- StorageClass: K3s `local-path`.

These settings need adjustment based on actual scrape cardinality, request volume, logs/second and free disk space. `local-path` is node-local: this is durable across some pod restarts, not across EC2/node loss. For production, use EBS-backed durable volumes or managed Prometheus/logging, an object store such as S3 for Loki, off-cluster backups, and a documented retention/compliance policy. Configure disk-space alerts and test a restore; PVCs are not backups.

## Troubleshooting

### Prometheus target absent or DOWN

1. `kubectl -n orderflow get svc,servicemonitor,endpoints`.
2. Confirm `kubectl -n orderflow get servicemonitor orderflow-orderflow -o yaml` (the resource name depends on release/chart naming) has label `release: kube-prometheus-stack`, endpoint port `http`, and path `/metrics`.
3. Confirm the Prometheus Operator CRDs exist and the Prometheus selector includes the release label.
4. From a temporary pod inside the cluster, curl `http://orderflow-orderflow.orderflow.svc.cluster.local/metrics` (service DNS may differ if you customized the release name).
5. If using the protected Traefik route, verify the actual PodCIDR and request source IP.

### Metrics endpoint returns 403 from in-cluster Prometheus

The `ipAllowList` may not match the source IP used by your K3s networking. Check the source IP/pod CIDR, then restrict to the correct cluster PodCIDR; never remove the allow-list as a quick fix. Direct ClusterIP scraping should not traverse the Ingress middleware.

### Dashboard missing

Check `kubectl -n monitoring get configmap orderflow-overview-dashboard --show-labels`. The label must be `grafana_dashboard=1`, and Grafana sidecar dashboard search namespace must include `monitoring` (`ALL` in this configuration). Check Grafana pod logs for provisioning errors.

### Logs absent in Loki

1. `kubectl -n monitoring logs deploy/alloy` and inspect component health/config errors.
2. Check `kubectl -n monitoring get pods` and whether Loki gateway/service is Ready.
3. Query `{namespace="orderflow"}` in Grafana Explore → Loki.
4. Verify that Alloy's `loki.write` URL matches the actual gateway service name in `monitoring`.

### Pod pending / OOMKilled

Inspect `kubectl describe pod`, `kubectl top nodes` and `kubectl top pods -A`. This stack is not appropriate for an undersized node. Increase EC2 RAM/disk or reduce retention/scrape load; do not simply delete PVCs.

### Alerts do not notify anyone

The custom rules only create alerts. External routing/receivers are intentionally not configured. Add a receiver and secret-managed credentials, then perform an end-to-end notification test.

## Production gaps to discuss honestly in an interview

1. **Availability:** one EC2 node is a single point of failure; production could use EKS or multi-node K3s, HA control plane and spread workloads across failure domains.
2. **Data durability:** local-path PVCs live with the node; production should use S3/object storage for Loki, durable network storage where applicable, backups and restore drills.
3. **Alert delivery:** wire Alertmanager to a real receiver, define ownership/escalation, and run a fault-injection exercise.
4. **Access control:** use SSO/RBAC for Grafana, protect Argo CD UI/API, and keep observability endpoints private.
5. **Secrets:** move credentials to AWS Secrets Manager/external-secrets and rotate them.
6. **Capacity:** establish SLOs, scrape intervals, cardinality limits, log volume/retention budget, resource requests/limits, and disk alerts from measured data.
7. **Change control:** keep chart versions pinned, update through PRs, validate with `helm lint`/`helm template`/schema checks and monitor upgrades.

Interview framing:

> “For the portfolio I use a single-node K3s deployment to control cost, but preserve production patterns: declarative Argo CD ownership, Prometheus Operator discovery via ServiceMonitor, pinned Helm chart versions, private metrics, persistent storage, seven-day retention, application RED metrics, Kubernetes saturation signals, Loki log aggregation with Alloy, provisioned dashboards, and actionable alert rules. I explicitly document that HA, object storage, external alert delivery, SSO and disaster recovery are the next production requirements rather than claiming this one-node setup is highly available.”

## Official references

- kube-prometheus-stack: https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack
- Prometheus Operator ServiceMonitor: https://prometheus-operator.dev/docs/developer/getting-started/
- Grafana Alloy Kubernetes install: https://grafana.com/docs/alloy/latest/set-up/install/kubernetes/
- Alloy Kubernetes log collection: https://grafana.com/docs/alloy/latest/collect/logs-in-kubernetes/
- Loki Helm installation and deployment modes: https://grafana.com/docs/loki/latest/setup/install/helm/
- Loki monolithic chart: https://grafana.com/docs/loki/latest/setup/install/helm/install-monolithic/
- Grafana provisioning: https://grafana.com/docs/grafana/latest/administration/provisioning/
- FastAPI Instrumentator: https://github.com/trallnag/prometheus-fastapi-instrumentator
