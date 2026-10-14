# Phase 6 bootstrap

This directory contains the one-time/manual bootstrap required before Argo CD can reconcile the GitOps application.

## Flow

1. Create the EC2 instance and attach an IAM instance profile with ECR pull-only permissions.
2. Install K3s.
3. Install Argo CD.
4. Configure the Argo CD repository credential using a dedicated GitHub App with read-only access to `orderflow-gitops`.
5. Create the non-Git database Secret `orderflow-db`.
6. Configure the short-lived ECR pull Secret refresh timer.
7. Apply `argocd/project.yaml` and `argocd/application.yaml`.
8. Argo CD syncs `helm/orderflow` from `main`.

The Kubernetes desired state remains in Git; repository and runtime secrets are intentionally bootstrapped outside Git for now. A later secrets-management phase can move these to AWS Secrets Manager / an external secret mechanism.
