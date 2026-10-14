# Phase 6 — K3s + Argo CD + real GitOps deployment

## Target architecture

```text
orderflow-app
     │
     ▼
GitHub Actions
     │
     ├── Test
     ├── Security gates
     ├── Docker build
     ├── Trivy
     └── ECR push
             │
             ▼
        Amazon ECR
       sha-<git-sha>
             │
             ▼
    GitOps promotion PR
             │
             ▼
     orderflow-gitops
          Helm
             │
             ▼
          Argo CD
             │
             ▼
        K3s on EC2
       ┌─────┴─────┐
       │           │
 OrderFlow API   PostgreSQL
       │
       ▼
    Traefik
       │
       ▼
   Internet :80
```

## Version baseline

This implementation uses K3s `v1.36.5+k3s1` and Argo CD `v3.5.3`. K3s v1.36.5 is a stable release; Argo CD 3.5 documents Kubernetes v1.36 as a tested Kubernetes version.

We use K3s `v1.36.5+k3s1` rather than blindly using the newest K3s release. K3s `v1.36.5+k3s1` is a stable release, and Argo CD `3.5` documents Kubernetes `1.36` among its tested versions. We selected versions based on compatibility and stability rather than always taking the newest release.

## Phase 6 execution order

```text
1. AWS EC2
      ↓
2. Security Group
      ↓
3. IAM role for ECR pull
      ↓
4. Install K3s
      ↓
5. Verify Kubernetes
      ↓
6. Install Argo CD v3.5.3
      ↓
7. Verify Argo CD
      ↓
8. Give Argo CD read access to GitOps repo
      ↓
9. Create PostgreSQL Secret
      ↓
10. Configure ECR image-pull authentication
      ↓
11. Apply Argo CD Project
      ↓
12. Apply Argo CD Application
      ↓
13. Argo CD syncs Helm
      ↓
14. PostgreSQL starts
      ↓
15. Migration runs
      ↓
16. OrderFlow starts
      ↓
17. Traefik exposes API
      ↓
18. Test /health and /ready
```

## 1. AWS EC2

Recommended portfolio baseline:

- Ubuntu 24.04 LTS x86_64
- 2 vCPU / 8 GiB RAM preferred for comfortable operation
- 20–30 GiB gp3 EBS for this phase
- Public IPv4 for the demo API, or a load balancer later
- Security group inbound:
  - TCP 22 from your own public IP only
  - TCP 80 from `0.0.0.0/0` for the demo API
  - TCP 8080 from `0.0.0.0/0` for the ARGOCD UI/orderflow-API testing. 
  - TCP 443 from `0.0.0.0/0` if TLS is added later
- Do not expose K3s API port 6443 publicly for this portfolio setup; administer the cluster over SSH.

Attach an EC2 instance profile with `AmazonEC2ContainerRegistryPullOnly`. The instance role is used only for ECR image pulls; the application container does not receive AWS credentials.

```text
1. Create the EC2 instance
start with one EC2 instance acting as the entire K3s server. (c7i-flex.large class is reasonable)

2. Create the Security Group
| Port | Source | Purpose |
|---|---|---|
| 22 | Your public IP `/32` | SSH |
| 80 | `0.0.0.0/0` | OrderFlow HTTP |
| 443 | `0.0.0.0/0` | Future HTTPS |
| 6443 | Your IP `/32` only, if you need direct remote `kubectl` | Kubernetes API |
| 8080 | `0.0.0.0/0` | OrderFlow HTTP (port worwaring testing) |

3. Create the EC2 IAM role
role name: ec2-Ecr-Pull
Attach an EC2 IAM role that allows the machine to pull from ECR

AmazonEC2ContainerRegistryPullOnly add -> inline policy to it.
And verify AWS identity from the instance: aws sts get-caller-identity

INSTALL AWS CLI: 
sudo apt install -y curl unzip
curl -fsSL https://awscli.amazonaws.com/v2/install.sh -o install-aws-cli.sh
sudo bash install-aws-cli.sh --system
aws --version
```

## 2. Install K3s

From the EC2 host:

K3s officially documents the installation script:
curl -sfL https://get.k3s.io | sh -
After installation:

sudo systemctl status k3s

Verify:

sudo k3s kubectl get nodes
NAME      STATUS   ROLES
...       Ready    control-plane,master

K3s installs kubectl and writes its kubeconfig to: /etc/rancher/k3s/k3s.yaml


CHECKPOINT 1
AWS
 └── EC2
      └── K3s
           └── Node = Ready

or try below bootstarp scripts 
```bash
sudo /path/to/orderflow-gitops/bootstrap/k3s/install-k3s.sh
```

Verify:

```bash
sudo k3s kubectl get nodes -o wide
sudo k3s kubectl get pods -A
```

K3s installs Traefik and the local-path storage provider by default. Traefik will provide the Ingress entry point and local-path will back the demo PostgreSQL PVC.

## 3. Install Argo CD

The official Argo CD v3.5.3 release provides the non-HA installation command:

kubectl create namespace argocd  --> Create ArgoCD namespace

kubectl apply \
  -n argocd \
  --server-side \
  --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/v3.5.3/manifests/install.yaml

verify:
kubectl get pods -n argocd
kubectl get svc -n argocd

Then retrieve the initial admin password:

kubectl -n argocd \
  get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d

or try below bootstrap scripts

```bash
sudo /path/to/orderflow-gitops/bootstrap/argocd/install-argocd.sh
```

Verify:

```bash
kubectl -n argocd get pods
```

Retrieve the initial admin password only for the bootstrap:

```bash
/path/to/orderflow-gitops/bootstrap/argocd/show-argocd-password.sh
```

For the demo UI, keep the Argo CD server private and use an SSH tunnel instead of exposing the admin API publicly:

On EC2:

```bash
kubectl -n argocd port-forward svc/argocd-server 8080:443 --address 127.0.0.1
```

From your workstation:

```bash
ssh -i <key.pem> -L 8080:127.0.0.1:8080 ubuntu@<EC2_PUBLIC_IP>
```

Open `https://localhost:8080`.

or 

If want to expose API publicly (not recommended)

sudo kubectl port-forward svc/argocd-server -n argocd 8080:80 --address 0.0.0.0

Access ArgoCD UI: http://ec2-public-ip:8080

## 4. Configure private Git access for Argo CD

Argo CD officially supports GitHub App authentication, and the GitHub App needs at least read-only Contents permission.
Create a dedicated GitHub App for Argo CD. Do not reuse the CI writer credential for cluster read access. Install it only on `orderflow-gitops` with read-only `Contents` permission. Here, Argo CD can read the desired state, but it does not need write access to the GitOps repository.


Create the dedicated Argo CD GitHub App
```text
1. Open GitHub Developer Settings → GitHub Apps
2. Click New GitHub App.
3. Configure the app name as orderflow-argocd-reader (or another globally available name).
4. Set the homepage URL to your GitHub profile or project repository.
5. Under Repository permissions, set the following:
Contents    Read-only
Metadata   Read-only

6. Leave webhook configuration disabled
7. Create the app.

Now Install the app on only orderflow-gitops:
1. On the new app's settings page, choose Install App.
2. Select the GitHub account or organization that owns orderflow-gitops.
3. Choose Only select repositories.
4. Select orderflow-gitops only. Do not select orderflow-app unless you have a separate reason for Argo CD  to read that repository.
5. Review and approve the installation.
Collect the three credentials Argo CD needs
App ID, Installation ID (optional ARGO can recognize the this ID itself), Private key (under the app's Private keys section, click Generate a private key and securely save the downloaded .pem file)
```

On the EC2 host:

The official Argo CD documentation says the Installation ID is optional for GitHub.com: Argo CD can discover it automatically.

```bash
export GITHUB_APP_ID='<read-only-app-id>'
(optional) export GITHUB_APP_INSTALLATION_ID='<installation-id>' 
export GITHUB_APP_PRIVATE_KEY_PATH='$HOME/orderflow-argocd-reader.pem'
export GITOPS_REPO_URL='https://github.com/<owner>/orderflow-gitops'

/path/to/orderflow-gitops/bootstrap/argocd/configure-github-app-repo.sh
```
Or USE ArgooCD UI

```text
1. Open your Argo CD web interface and log in.
2. Navigate to Settings → Repositories.
3. Click Connect Repo using GitHub App.
4. Enter the following details:
    Repository URL | https://github.com/OWNER/orderflow-gitops.git |
    | App ID | ID of orderflow-argocd-reader |
    | Private key | Contents of the downloaded .pem file |
5. Click Connect and check the repository connection status.
These steps follow the official Argo CD GitHub App connection procedure.
```

The private key must never be committed to Git. Argo CD supports repository credentials using a GitHub App and requires at least read-only Contents access for this purpose.

## 5. Create the demo database Secret
The Secret must exist in the namespace where the pods consuming it run.
We must also configure your Deployment and PostgreSQL workload to consume the Secret.

OrderFlow API --> Reads credentials
PostgreSQL --> Initializes database access

Create Namespace ordeflow (app namespace): sudo k3s kubectl create namespace orderflow
```bash
/path/to/orderflow-gitops/bootstrap/argocd/create-orderflow-db-secret.sh
```

The secret contains:

- `POSTGRES_USER`
- `POSTGRES_PASSWORD`
- `POSTGRES_DB`
- `DATABASE_URL`

or 

sudo k3s kubectl create secret generic orderflow-db-secret \
  --namespace orderflow \
  --from-literal=POSTGRES_DB=orderflow \
  --from-literal=POSTGRES_USER=orderflow \
  --from-literal=POSTGRES_PASSWORD='REPLACE_WITH_A_STRONG_PASSWORD'
  --from-literal=DATABASE_URL='postgresql+psycopg://POSTGRES_USER:POSTGRES_PASSWORD@postgresql-svc:5432/POSTGRES_DB'

Verify:
sudo k3s kubectl get secret orderflow-db-secret \
  -n orderflow

NOTE: Make your PostgreSQL and Ordeflow deployments workloads consume the Secret

This is deliberately outside Git. The later secrets-management stage can replace this bootstrap Secret with AWS Secrets Manager / an external-secrets pattern.

## 6. Configure the private ECR pull Secret

The EC2 instance role provides the AWS identity. The bootstrap script refreshes a short-lived ECR auth token into the Kubernetes `ecr-registry` Secret.

```bash
export AWS_REGION='ap-south-1'
export ECR_REGISTRY='<account-id>.dkr.ecr.ap-south-1.amazonaws.com'

sudo -E /path/to/orderflow-gitops/bootstrap/ecr/install-ecr-refresh.sh
```

Check:
```bash
kubectl -n orderflow get secret ecr-registry
sudo systemctl status orderflow-ecr-pull.timer
```

The ECR authorization token is valid for 12 hours, so the timer refreshes it every 8 hours.

OR 

I recommend a Kubernetes image-pull Secret refreshed automatically by a CronJob using the EC2 instance's IAM role. That fits single-EC2 K3s demo without adding a new AWS user or storing long-lived AWS access keys.

Set the values on the EC2 instance:
export AWS_REGION="YOUR_AWS_REGION"
export AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
export ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
export K8S_NAMESPACE="orderflow"

Confirm the repository exists:
aws ecr describe-repositories \
  --repository-names orderflow-api \
  --region "$AWS_REGION"

Then test ECR authentication:
aws ecr get-login-password \
  --region "$AWS_REGION" >/dev/null \
  && echo "ECR authentication successful"

Above may fail so add Update the EC2 IAM role permissions:
Open the AWS IAM Roles console.
1. Search for k3-ec2-ecr-pull.
2. Open the role.
3. Select Add permissions → Create inline policy.
4. Switch to the JSON editor.
5. Add the following policy.

{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ECRAuthentication",
      "Effect": "Allow",
      "Action": "ecr:GetAuthorizationToken",
      "Resource": "*"
    },
    {
      "Sid": "OrderFlowRepositoryAccess",
      "Effect": "Allow",
      "Action": [
        "ecr:DescribeRepositories",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage"
      ],
      "Resource": "arn:aws:ecr:ap-southeast-2:934225420324:repository/orderflow-api"
    }
  ]
}

NOTE: This policy permits authentication, pulling the OrderFlow image, and checking repository metadata.

step1: Create the initial image-pull Secret
Use below script:

    #!/usr/bin/env bash
    set -euo pipefail
    umask 077

    AWS_REGION="ap-southeast-2"
    NAMESPACE="orderflow"
    SECRET_NAME="ecr-pull-secret"
    TMP_FILE="$(mktemp)"
    trap 'rm -f "$TMP_FILE"; unset ECR_PASSWORD' EXIT

    ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
    REGISTRY="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
    ECR_PASSWORD="$(aws ecr get-login-password --region "$AWS_REGION")"

    ECR_REGISTRY="$REGISTRY" ECR_PASSWORD="$ECR_PASSWORD" CONFIG_PATH="$TMP_FILE" python3 - <<'PY'
    import base64, json, os

    password = os.environ["ECR_PASSWORD"]
    registry = os.environ["ECR_REGISTRY"]
    auth = base64.b64encode(f"AWS:{password}".encode()).decode()

    config = {"auths": {registry: {
        "username": "AWS", "password": password, "auth": auth
    }}}

    with open(os.environ["CONFIG_PATH"], "w") as f:
        json.dump(config, f)
    PY

    k3s kubectl create secret generic "$SECRET_NAME" \
      -n "$NAMESPACE" --type=kubernetes.io/dockerconfigjson \
      --from-file=.dockerconfigjson="$TMP_FILE" --dry-run=client -o yaml |
      k3s kubectl apply -f -

    echo "ECR pull Secret refreshed successfully."

Save it to /usr/local/sbin/refresh-ecr-secret.sh, then run:
  sudo chmod 700 /usr/local/sbin/refresh-ecr-secret.sh
  sudo /usr/local/sbin/refresh-ecr-secret.sh

Verify:
sudo k3s kubectl get secret ecr-pull-secret \
  -n orderflow \
  -o jsonpath='{.type}{"\n"}'
Expected output: kubernetes.io/dockerconfigjson

Step 4 — Automate the refresh every 6 hours

  Open root's crontab: sudo crontab -e
  Add this line: 0 */6 * * * /usr/local/sbin/refresh-ecr-secret.sh >> /var/log/refresh-ecr-secret.log 2>&1

Above, refreshes the Secret every six hours, well before the ECR token's 12-hour expiration.

Check the schedule: sudo crontab -l

This approach is appropriate for portfolio project, but the EC2 IAM role is powerful infrastructure identity.

## 7. Apply the Argo CD Application

Edit the owner placeholder or use the helper:

```bash
export GITHUB_OWNER='<github-user-or-org>'
/path/to/orderflow-gitops/bootstrap/argocd/apply-orderflow-app.sh
```

Then:

```bash
kubectl -n argocd get application orderflow
kubectl -n argocd describe application orderflow
```

Argo CD should report the Application as progressing toward `Synced` / `Healthy`.

## 8. Expected sync ordering

The chart uses Argo CD sync waves so the first real deployment is deterministic:

```text
wave 0  -> PostgreSQL StatefulSet
           |
           v
wave 1  -> Alembic migration hook
           |
           v
wave 2  -> OrderFlow Deployment
```

This avoids running database migrations before PostgreSQL is available.

## 9. Validate the application

Watch:

```bash
kubectl -n orderflow get pods -o wide
kubectl -n orderflow get svc,ingress,pvc
kubectl -n orderflow get events --sort-by=.lastTimestamp
```

Then get the EC2 public IP and test:

```bash
curl http://<EC2_PUBLIC_IP>/health
curl http://<EC2_PUBLIC_IP>/ready
```

Expected:

```text
/health  -> healthy
/ready   -> ready
```

Swagger:

```text
http://<EC2_PUBLIC_IP>/docs
```

or 

TEST FROM LOCAL Machine git bash: 

APP readiness:
curl -i --resolve orderflow.local:80:EC2_PUBLIC_IP  http://orderflow.local/health

DB readiness:
curl -i --resolve orderflow.local:80:EC2_PUBLIC_IP http://orderflow.local/ready

Using port forwarding:

sudo kubectl port-forward svc/orderflow-orderflow -n orderflow  8080:80 --address 0.0.0.0

## 10. First real GitOps update

The important end-to-end proof is:

```text
new application commit
  -> orderflow-app CI
  -> tests/security
  -> Docker build
  -> Trivy pass
  -> ECR push sha-<commit>
  -> GitOps promotion PR
  -> GitOps Helm validation
  -> merge orderflow-gitops/main
  -> Argo CD detects Git change
  -> migration hook
  -> rolling update
  -> new OrderFlow pods
```

At no point does application CI call `kubectl apply` against the production cluster.

## 11. Failure tests for the interview story

After the first successful deployment, deliberately test:

1. Change only the GitOps image tag to a nonexistent ECR tag. Argo should report the workload as degraded because the image cannot be pulled.
2. Break a Helm value in a GitOps PR. GitOps CI should fail before the PR can merge.
3. Change the application image tag through a normal app commit. CI publishes the image and creates the promotion PR; Argo changes only after that GitOps PR is merged.
4. Make `/ready` fail by stopping PostgreSQL. Kubernetes should keep the API out of Ready state while the process can remain alive.

## Production trade-off

This portfolio implementation uses a single K3s server node on EC2 for cost and learning velocity. PostgreSQL is also single-node here and uses local-path storage, so this is not an HA production database design. In a larger AWS production environment, evaluate EKS or a multi-node K3s design and use a managed PostgreSQL service such as RDS based on availability, operations, recovery, and cost requirements.


## Architectral ARGOCD Manifets

The third repository is My architectural recommendation for organization-style simulation, not a mandatory Argo CD rule.

Repository name: orderflow-platform-config
Owns Argo CD AppProject policies, Application and later ApplicationSet declarations, cluster-level configuration, and declarations for platform add-ons such as observability.

This mirrors a common organizational separation between application development, workload deployment configuration, and platform governance. he goal is clear ownership and access boundaries, not maximizing repository count.

REPO STRUCTURE:

orderflow-platform-config/
├── README.md
├── bootstrap/
│   ├── seed-project.yaml
│   └── root-application.yaml
│
├── argocd/
│   ├── kustomization.yaml
│   ├── projects/
│   │   └── orderflow-dev.yaml
│   ├── applications/
│   │   └── orderflow-dev.yaml
│   └── applicationsets/
│
├── clusters/
│   └── k3s-dev/
│
└── addons/
    └── observability/

This is an App-of-Apps-style bootstrap. Argo CD explicitly warns that the App-of-Apps pattern is an admin-only tool, because it can create applications in other projects. The platform repository must therefore be tightly protected, with reviewed changes restricted to trusted platform maintainers.

The two bootstrap manifests are the starting point. The root-application.yaml is initially applied to the cluster, and then Argo CD watches the platform configuration repository. Its managed configuration includes the AppProject and workload Application declarations.


## How the Argo CD YAMLs fit together

### AppProject
argocd/projects/orderflow-dev.yaml
Defines the deployment permissions: which GitOps repo is trusted, which cluster/namespace OrderFlow can target, and which Kubernetes resource types it may manage.

### Application

argocd/applications/orderflow-dev.yaml
Tells Argo CD to read the Helm chart from orderflow-gitops, apply the development values, and deploy the rendered resources into the orderflow namespace on the local K3s cluster.

### Bootstrap

bootstrap/root-application.yaml
Establishes the initial connection between Argo CD and orderflow-platform-config. Once installed, this root application allows Argo CD to reconcile the platform's declarative configuration.

## Trouble shooting

few imp commands:
-> sudo kubectl get pods -n orderflow
-> sudo kubectl get events -n orderflow
-> sudo kubectl get events  -n orderflow
-> sudo kubectl get deploy -n orderflow
-> sudo kubectl logs -f  <pod_name>  -n orderflow
-> sudo kubectl get secrets 
-> sudo kubectl describe pod orderflow-orderflow-postgresql-0  -n orderflow