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
