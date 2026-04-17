# Run the Terraform infrastructure configuration workflow

Repository for the **T4-03.04 - Examples and Real-World Workflows with Terraform** hands-on lesson.

The repo contains a standard Terraform project structure, and a GitHub Actions pipeline configured to run it.

## The scenario: what we're building?

A simple but realistic AWS setup:

- One **EC2 instance** (the application server)
- One **S3 bucket** (static assets/storage)
- Configured with **tags**, **variables**, and **outputs**
- Managed with **remote state**
- Deployed through a **CI/CD pipeline**

---

## Terraform Project Structure

```text
my-infra/
  main.tf               ← resource definitions
  variables.tf          ← input variable declarations
  outputs.tf            ← output value declarations
  terraform.tfvars      ← variable values (not committed if sensitive)
  .terraform.lock.hcl   ← provider version lock (commit this)
```

Terraform reads **all `.tf` files in the directory**. The file names aren't enforced but this convention is universal and immediately recognisable.

## Declaring inputs: `variables.tf`

```hcl
variable "region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "instance_type" {
  description = "EC2 instance size"
  type        = string
  default     = "t3.micro"
}

variable "bucket_name" {
  description = "Name for the S3 bucket (must be globally unique)"
  type        = string
}
```

- Variables with `default` → optional at apply time
- `bucket_name` has no default → must be supplied (S3 names are globally unique)
- Supply values via `terraform.tfvars`, `-var` flag, or environment variable

## Resource definitions: `main.tf`

```hcl
provider "aws" {
  region = var.region
}

resource "aws_instance" "app_server" {
  ami           = "ami-0c02fb55956c7d316"
  instance_type = var.instance_type

  tags = {
    Name        = "AppServer"
    Environment = "production"
  }
}

resource "aws_s3_bucket" "app_assets" {
  bucket = var.bucket_name

  tags = {
    Name        = "AppAssets"
    Environment = "production"
  }
}
```

- `var.region`, `var.instance_type`, `var.bucket_name` → reference the declared variables
- Tags are key-value metadata → essential for cost allocation and resource management in real teams

## Surfacing values after apply: `outputs.tf`

```hcl
output "instance_public_ip" {
  description = "Public IP address of the EC2 instance"
  value       = aws_instance.app_server.public_ip
}

output "bucket_arn" {
  description = "ARN of the S3 bucket"
  value       = aws_s3_bucket.app_assets.arn
}
```

Outputs serve two purposes:

1. **Display** useful values after `terraform apply` (like the server's IP address)
2. **Pass values** between Terraform modules → one module's outputs feed another's inputs

---

## The init → plan → apply workflow in action

### Step 1: setting up the project

```bash
$ terraform init

Initializing provider plugins...
- Installing hashicorp/aws v5.31.0...
Terraform has been successfully initialized!
```

- Downloads the AWS provider plugin into `.terraform/`
- Creates `.terraform.lock.hcl` to lock provider versions
- **Commit:** `.terraform.lock.hcl` ✅
- **Don't commit:** `.terraform/` directory ❌ (add to `.gitignore`)

### Step 2: review before you apply

```bash
$ terraform plan -var='bucket_name=my-assets-20240115'

  # aws_instance.app_server will be created
  + resource "aws_instance" "app_server" {
      + ami           = "ami-0c02fb55956c7d316"
      + instance_type = "t3.micro"
    }

  # aws_s3_bucket.app_assets will be created
  + resource "aws_s3_bucket" "app_assets" {
      + bucket = "my-assets-20240115"
    }

Plan: 2 to add, 0 to change, 0 to destroy.
```

**Symbol key:**
- `+` → create  `~` → modify in place  `-` → destroy

### Step 3: making the changes

```bash
$ terraform apply -var='bucket_name=my-assets-20240115'

...

[plan output]

...

Do you want to perform these actions? (yes/no): yes

aws_s3_bucket.app_assets: Creating...        [2s]
aws_instance.app_server: Creating...         [42s]

Apply complete! Resources: 2 added, 0 changed.

Outputs:
bucket_arn         = "arn:aws:s3:::my-assets-20240115"
instance_public_ip = "54.123.45.67"
```

- Terraform asks for confirmation before proceeding
- Resources are created (they may create in parallel when there are no dependencies)
- Outputs are displayed (the IP and ARN you need immediately after provisioning)

> **Note:** in the CI/CD pipeline configured in the repository, we provide the value of `bucket_name` as an environment variable configured as a GitHub secret; you can notice the `env: TF_VAR_bucket_name: ${{ secrets.S3_BUCKET_NAME }}`; thanks to this, in that case, you can simply issue `terraform plan` and `terraform apply` commands without the `-var` flag.

---

## Remote state and the problem with local state

- Local `terraform.tfstate` → fine for solo work
- In a team
  - two engineers running `apply` simultaneously → state collision → broken infrastructure

The solution is configuring a remote state: store state in a **shared, locked backend**. Standard AWS pattern:
- **S3 bucket** → stores the state file
- **DynamoDB table** → provides state locking (prevents concurrent runs)

**S3 Backend Configuration for remote state**

```hcl
terraform {
  backend "s3" {
    bucket         = "my-terraform-state-bucket"
    key            = "my-infra/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "my-terraform-locks"
  }
}
```

After adding this block, run `terraform init` again and Terraform will migrate local state to S3.

> **Note:** in the repository, we directly provide the infrastructure configuration supporting remote state.

---

## Running Terraform in a GitHub Actions CI/CD pipeline (plan on PR, apply on merge)

```yaml
name: Terraform

on:
  push:       { branches: [main] }
  pull_request: { branches: [main] }

jobs:
  terraform:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: hashicorp/setup-terraform@v3

      - run: terraform init

      - name: Plan (PRs only)
        run: terraform plan
        if: github.event_name == 'pull_request'

      - name: Apply (merges to main only)
        run: terraform apply -auto-approve
        if: github.ref == 'refs/heads/main' && github.event_name == 'push'
    env:
      AWS_ACCESS_KEY_ID:     ${{ secrets.AWS_ACCESS_KEY_ID }}
      AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
```

**The Professional Team Workflow**

| Event | What runs | Who sees it |
|-------|----------|-------------|
| Pull Request opened/updated | `terraform plan` | Reviewer sees plan output in PR |
| PR merged to main | `terraform apply` | Infra changes automatically applied |

- AWS credentials stored as **GitHub Actions secrets** → never hardcoded
- Infra changes go through the **same review process as application code**
- Apply only runs after a PR is reviewed and merged → no unreviewed infra changes in production

> > **Note:** this pattern is sometimes called **GitOps for infrastructure**.
