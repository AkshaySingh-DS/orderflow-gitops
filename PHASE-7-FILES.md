# Phase 7 files in this repository

This change-only bundle uses `orderflow-platform-config` for platform-wide Argo CD Applications and observability configuration. Follow `README.md` for safe, staged rollout and prerequisite secrets.

The initial kustomization installs kube-prometheus-stack, Loki, and Alloy. After their CRDs/services are healthy, uncomment the alert-rule and dashboard applications in `clusters/k3s-dev/kustomization.yaml`; deploy the OrderFlow ServiceMonitor only after the Prometheus Operator CRDs are available.
