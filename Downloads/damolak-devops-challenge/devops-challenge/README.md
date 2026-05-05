# Damolak DevOps Challenge — Production-Ready ECS Deployment

## Architecture Overview

```
                           ┌─────────────────────────────────────────────┐
                           │                   AWS Cloud                  │
                           │                                              │
  Developer                │   ┌──────────┐      ┌──────────────────┐   │
  Push to main ───────────►│   │ ECR Repo │      │  CloudWatch      │   │
        │                  │   │  (image) │      │  Logs + Alarms   │   │
        ▼                  │   └────┬─────┘      └────────┬─────────┘   │
  ┌──────────────┐         │        │                     ▲             │
  │ GitHub       │Build+Push│        ▼                     │             │
  │ Actions      │─────────►  ┌───────────────────────────────────┐     │
  └──────────────┘         │  │            VPC (10.0.0.0/16)      │     │
                           │  │  ┌──────────────────────────────┐ │     │
                           │  │  │  Public Subnets (2 AZs)      │ │     │
                           │  │  │  ┌────────────────────────┐  │ │     │
  Internet ───────────────►│  │  │  │  Application Load      │  │ │     │
                           │  │  │  │  Balancer (ALB)        │  │ │     │
                           │  │  │  └──────────┬─────────────┘  │ │     │
                           │  │  └─────────────┼────────────────┘ │     │
                           │  │                │                   │     │
                           │  │  ┌─────────────┼────────────────┐ │     │
                           │  │  │  Private Subnets (2 AZs)     │ │     │
                           │  │  │  ┌──────────┴──────────────┐ │ │     │
                           │  │  │  │   ECS Fargate Cluster   │ │ │     │
                           │  │  │  │  ┌────────┐ ┌────────┐  │ │ │     │
                           │  │  │  │  │Task 1  │ │Task 2  │  │ │ │     │
                           │  │  │  │  │:8080   │ │:8080   │  │ │ │     │
                           │  │  │  │  └────────┘ └────────┘  │ │ │     │
                           │  │  │  └─────────────────────────┘ │ │     │
                           │  │  └──────────────────────────────┘ │     │
                           │  └───────────────────────────────────┘     │
                           └─────────────────────────────────────────────┘
```

### Key Design Decisions

**ECS Fargate over EC2/EKS**: Fargate eliminates node management, patching, and capacity planning. For a microservice of this scale it's the right default — you pay per task, not per idle EC2 instance. EKS adds significant operational overhead that isn't warranted until you have multiple services.

**Private subnets for tasks**: ECS tasks run in private subnets with no public IP. All inbound traffic goes through the ALB, reducing the attack surface. Outbound internet access is via a NAT Gateway.

**Multi-AZ**: Two Availability Zones for both subnets and tasks. This means a single AZ outage has zero impact on availability.

**GitHub Actions as CI/CD**: The pipeline runs entirely within GitHub — no additional infrastructure required. OIDC-based authentication means no long-lived AWS credentials are stored as secrets. The workflow triggers automatically on every push to `main`.

**Modular Terraform**: Three modules (`vpc`, `ecr`, `ecs`) plus a `monitoring` module. Each is independently testable and reusable across environments.

**Deployment circuit breaker**: ECS deployment circuit breaker is enabled with automatic rollback. A bad deployment that fails health checks rolls back without manual intervention.

**Auto Scaling**: CPU-based target tracking — scale out when CPU > 70%, scale in after a cooldown. Min 1 task, max 4 tasks.

---

## Repository Structure

```
.
├── app/
│   ├── app.py               # Flask microservice
│   ├── test_app.py          # Pytest test suite
│   ├── requirements.txt
│   └── Dockerfile           # Multi-stage, non-root user
├── terraform/
│   ├── modules/
│   │   ├── vpc/             # VPC, subnets, NAT, security groups
│   │   ├── ecr/             # ECR repository + lifecycle policy
│   │   ├── ecs/             # ECS cluster, task def, ALB, auto scaling
│   │   └── monitoring/      # CloudWatch dashboard, alarms, SNS
│   └── environments/
│       └── prod/            # Root module wiring all modules together
├── .github/workflows/
│   └── ci-cd.yml            # GitHub Actions CI/CD pipeline
├── scripts/
│   ├── bootstrap-state.sh   # One-time: creates S3 bucket + DynamoDB lock table
│   └── setup-oidc.sh        # One-time: creates IAM OIDC provider + role for GitHub Actions
├── docker-compose.yml       # Local development
└── README.md
```

---

## Prerequisites

| Tool | Version | Purpose |
|------|---------|---------|
| AWS CLI | v2 | Interacting with AWS |
| Terraform | >= 1.6 | Provisioning infrastructure |
| Docker | >= 24 | Building/running the container |
| Python | 3.12 | Running the app and tests locally |

AWS credentials must have permissions for: ECS, ECR, EC2/VPC, IAM, CloudWatch, S3 (state backend), DynamoDB (state locking).

---

## Deployment Steps

### 1. Bootstrap Terraform Remote State

Before the first `terraform apply`, create the S3 bucket and DynamoDB lock table. The script is idempotent — safe to re-run:

```bash
export AWS_REGION=eu-west-1
chmod +x scripts/bootstrap-state.sh
./scripts/bootstrap-state.sh
```

This creates the `damolak-terraform-state` S3 bucket (versioned, encrypted, public access blocked) and the `damolak-terraform-locks` DynamoDB table.

### 2. Provision Infrastructure

```bash
cd terraform/environments/prod

# Copy and fill in your values
cp terraform.tfvars.example terraform.tfvars

# Initialise (downloads providers, configures backend)
terraform init

# Review what will be created
terraform plan

# Apply (takes ~5 minutes)
terraform apply
```

At the end of apply, Terraform prints the outputs including `app_url` — the ALB DNS name.

### 3. Build and Push the Docker Image

```bash
# Get ECR URL from Terraform output
ECR_URL=$(terraform -chdir=terraform/environments/prod output -raw ecr_repo_url)
AWS_REGION=eu-west-1

# Authenticate Docker to ECR
aws ecr get-login-password --region $AWS_REGION | \
  docker login --username AWS --password-stdin $ECR_URL

# Build and push
docker build -t $ECR_URL:latest app/
docker push $ECR_URL:latest
```

### 4. Deploy via CI/CD

**GitHub Actions**:

1. Create the OIDC provider and IAM role in AWS (one-time setup):

```bash
export AWS_REGION=eu-west-1
export GITHUB_ORG=<your-github-username-or-org>
export GITHUB_REPO=<your-repo-name>
chmod +x scripts/setup-oidc.sh
./scripts/setup-oidc.sh
```

The script prints the `AWS_ROLE_ARN` value at the end.

2. Add one repository secret in GitHub → Settings → Secrets → Actions:
   - `AWS_ROLE_ARN` — the ARN printed by the script above

3. Push to `main` — the pipeline in `.github/workflows/ci-cd.yml` triggers automatically.

### 5. Local Development

```bash
# Run locally with Docker Compose
docker compose up --build

# Test endpoints
curl http://localhost:8080/
curl http://localhost:8080/health
curl http://localhost:8080/metrics

# Run tests
cd app && pip install -r requirements.txt && pytest -v
```

---

## CI/CD Pipeline Flow

```
Push to main
     │
     ▼
 ┌────────┐    ┌────────┐    ┌──────────────┐    ┌──────────────┐    ┌─────────┐
 │ Test   │───►│ Build  │───►│ Smoke Test   │───►│ Push to ECR  │───►│ Terraform│
 │(pytest)│    │(docker)│    │(health check)│    │              │    │  Apply  │
 └────────┘    └────────┘    └──────────────┘    └──────────────┘    └────┬────┘
                                                                           │
                                                                           ▼
                                                                   ┌──────────────┐
                                                                   │ ECS Deploy   │
                                                                   │(wait stable) │
                                                                   └──────────────┘
```

Each stage must pass before the next runs. A failed deployment triggers automatic ECS rollback via the deployment circuit breaker.

---

## Monitoring & Alerting

### CloudWatch Dashboard

After deployment, the dashboard is available in the AWS Console:
**CloudWatch → Dashboards → `damolak-devops-app-dashboard`**

It shows:
- ECS CPU and Memory utilization (5-minute averages)
- ALB request count and 5xx error rate
- Live application log tail

### Alarms

| Alarm | Trigger | Action |
|-------|---------|--------|
| CPU High | CPU > 80% for 10 min | SNS alert |
| Memory High | Memory > 80% for 10 min | SNS alert |
| ALB 5xx | > 10 errors in 1 minute | SNS alert |
| Unhealthy Hosts | Any unhealthy ECS task | SNS alert |
| App Error Rate | > 5 ERROR logs/min | SNS alert |

Set `alert_email` in `terraform.tfvars` to receive email alerts.

### Viewing Logs

```bash
# Stream live application logs
aws logs tail /ecs/damolak-devops-app --follow --region eu-west-1

# Search for errors in the last hour
aws logs filter-log-events \
  --log-group-name /ecs/damolak-devops-app \
  --start-time $(date -d '1 hour ago' +%s000) \
  --filter-pattern "ERROR"
```

---

## Application Endpoints

| Endpoint | Description |
|----------|-------------|
| `GET /` | Service info (version, environment, host) |
| `GET /health` | Health check — returns 200 if healthy |
| `GET /ready` | Readiness check |
| `GET /metrics` | Basic runtime metrics |

---

## Assumptions

- AWS account and region (`eu-west-1`) are pre-configured in AWS CLI
- The S3 bucket and DynamoDB table for Terraform state are created manually before the first `terraform apply` (see Step 1 above)
- GitHub Actions OIDC is configured in IAM (no long-lived access keys stored in secrets)
- A single environment (`prod`) is shown; adding `staging` would mean duplicating `terraform/environments/prod` with different variable values

---

## Limitations & Potential Improvements

**HTTPS / TLS**: The ALB listener is HTTP only. In production, attach an ACM certificate and redirect port 80 → 443. This requires a domain name.

**Secrets Management**: Environment variables are passed directly. Sensitive values should be stored in AWS Secrets Manager or SSM Parameter Store and referenced from the task definition.

**Multi-environment**: The Terraform structure supports it (just add `terraform/environments/staging`), but only `prod` is implemented in this challenge.

**Database**: This is a stateless microservice. A real app would add RDS (Postgres) in the private subnets with a separate security group.

**WAF**: An AWS WAF web ACL on the ALB would add rate limiting and bot protection.

**Observability**: CloudWatch is the baseline. Datadog or Grafana Cloud would give better dashboards, distributed tracing, and on-call alerting integrations.

**Cost**: NAT Gateway (~$32/month) is the biggest fixed cost. For a dev environment, you can remove it and assign public IPs to ECS tasks (not recommended for production).
