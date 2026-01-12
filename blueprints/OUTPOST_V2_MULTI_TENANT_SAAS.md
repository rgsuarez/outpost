# Outpost V2 Multi-Tenant SaaS — Implementation Blueprint

> **Document Status**: Active
> **Last Updated**: 2026-01-11
> **Owner**: Platform Team

<!-- BLUEPRINT METADATA (DO NOT REMOVE) -->
<!-- _blueprint_version: 2.0.1 -->
<!-- _generated_at: 2026-01-11T19:30:00Z -->
<!-- _generator: claude-opus-4-5 (manual) -->
<!-- _depth: 3 -->
<!-- _tiers_generated: T0, T1, T2, T3, T4 -->
<!-- END METADATA -->

---

## Strategic Vision

Transform Outpost from a single-operator EC2+SSM tool into a production-grade multi-tenant SaaS platform. The architecture prioritizes **pay-per-use economics** — near-zero cost when idle (<$15/month), linear scaling to 1000+ concurrent users.

**Core Architecture:**
- **API Gateway + Lambda** — Request handling, authentication, rate limiting
- **SQS + ECS Fargate** — Queue-based job processing with auto-scaling (0-20 workers)
- **DynamoDB** — Tenant/job metadata, usage tracking, audit trails
- **Secrets Manager** — Per-tenant BYOK credential storage
- **Stripe** — Subscription billing (Free/Pro/Enterprise tiers)

**Critical Constraint:** Infrastructure must cost <$15/month when completely idle. All compute is Fargate (pay-per-use), no always-on EC2.

---

## Success Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| Idle monthly cost | < $15 | AWS Cost Explorer (no active jobs for 30 days) |
| API authentication latency | < 50ms p99 | CloudWatch API Gateway metrics |
| Job dispatch latency | < 200ms p99 | SQS message age at consumption |
| Concurrent tenants | 100+ | Active API keys with jobs in-flight |
| Worker scale-up time | < 60 seconds | ECS task launch to running |
| Worker scale-down to zero | < 15 minutes idle | ECS desired count = 0 |
| Audit trail coverage | 100% | All API calls logged to DynamoDB |
| Billing accuracy | 100% | Stripe invoice matches usage records |

---

## Execution Configuration

```yaml
execution:
  shell: bash
  shell_flags: ["-e", "-o", "pipefail"]
  max_parallel_tasks: 4

  resource_locks:
    - name: "terraform_state"
      type: exclusive
    - name: "dynamodb_schema"
      type: exclusive
    - name: "stripe_config"
      type: exclusive
    - name: "ecr_push"
      type: exclusive

  preflight_checks:
    - command: "aws --version"
      expected_exit_code: 0
      error_message: "AWS CLI v2 required"
    - command: "terraform --version"
      expected_exit_code: 0
      error_message: "Terraform >= 1.5 required"
    - command: "docker info"
      expected_exit_code: 0
      error_message: "Docker must be running"
    - command: "python3 --version"
      expected_exit_code: 0
      error_message: "Python 3.11+ required"
    - command: "test -f ~/.aws/credentials"
      expected_exit_code: 0
      error_message: "AWS credentials not configured"

  secret_resolution:
    on_missing: abort
    sources:
      - type: env
        prefix: "OUTPOST_"
      - type: file
        path: ".env"
      - type: aws_ssm
        prefix: "/outpost/prod/"
```

---

## Tier 0: Foundation — Terraform Backend & Core Infrastructure

### T0.1: Terraform S3 Backend

```yaml
task_id: T0.1
name: "Configure Terraform S3 backend for state management"
status: not_started
assignee: null
estimated_sessions: 1
dependencies: []

input_bindings: {}

interface:
  input: "AWS account ID, region, project name"
  input_type: none
  output: "S3 bucket and DynamoDB table for Terraform state"
  output_type: json
  output_schema:
    type: object
    properties:
      bucket_name: { type: string }
      dynamodb_table: { type: string }
      region: { type: string }
    required: [bucket_name, dynamodb_table, region]

output:
  location: file
  path: "/tmp/blueprint/T0.1/output.json"
  ports:
    backend_config:
      type: json

required_capabilities:
  - aws-cli
  - terraform

acceptance_criteria:
  - "S3 bucket exists with versioning enabled"
  - "DynamoDB table exists for state locking"
  - "backend.tf references correct bucket and table"
  - "terraform init succeeds with remote backend"

verification:
  smoke:
    command: "aws s3 ls s3://outpost-terraform-state-311493921645 --profile soc"
    timeout: PT10S
  unit:
    command: "cd infrastructure/terraform && terraform init -backend=true"
    timeout: PT2M

rollback: "aws s3 rb s3://outpost-terraform-state-311493921645 --force --profile soc && aws dynamodb delete-table --table-name outpost-terraform-locks --profile soc"

on_failure:
  max_retries: 1
  action: block
```

#### T0.1.1: Create S3 State Bucket

```yaml
task_id: T0.1.1
name: "Create S3 bucket for Terraform state"
status: not_started
dependencies: []

input_bindings: {}

interface:
  input: "AWS account ID (311493921645), region (us-east-1)"
  output: "S3 bucket ARN with versioning and encryption"

output:
  location: file
  path: "/tmp/blueprint/T0.1.1/output.json"
  ports:
    bucket_arn:
      type: string

acceptance_criteria:
  - "Bucket name: outpost-terraform-state-311493921645"
  - "Versioning enabled"
  - "Server-side encryption with AES-256"
  - "Block all public access"

verification:
  smoke:
    command: "aws s3api head-bucket --bucket outpost-terraform-state-311493921645 --profile soc"
    timeout: PT10S

rollback: "aws s3 rb s3://outpost-terraform-state-311493921645 --force --profile soc"

files_to_create:
  - infrastructure/terraform/bootstrap/s3_backend.tf
```

#### T0.1.2: Create DynamoDB Lock Table

```yaml
task_id: T0.1.2
name: "Create DynamoDB table for Terraform state locking"
status: not_started
dependencies: [T0.1.1]

input_bindings:
  bucket:
    source: T0.1.1
    output_port: bucket_arn
    transfer: memory
    required: true

interface:
  input: "Region from T0.1.1"
  output: "DynamoDB table ARN"

output:
  location: file
  path: "/tmp/blueprint/T0.1.2/output.json"
  ports:
    table_arn:
      type: string

acceptance_criteria:
  - "Table name: outpost-terraform-locks"
  - "Partition key: LockID (String)"
  - "On-demand billing mode (pay-per-use)"

verification:
  smoke:
    command: "aws dynamodb describe-table --table-name outpost-terraform-locks --profile soc --query 'Table.TableStatus' --output text | grep ACTIVE"
    timeout: PT10S

rollback: "aws dynamodb delete-table --table-name outpost-terraform-locks --profile soc"

files_to_create:
  - infrastructure/terraform/bootstrap/dynamodb_lock.tf
```

#### T0.1.3: Create Backend Configuration

```yaml
task_id: T0.1.3
name: "Create backend.tf configuration file"
status: not_started
dependencies: [T0.1.1, T0.1.2]

input_bindings:
  bucket:
    source: T0.1.1
    output_port: bucket_arn
    transfer: memory
    required: true
  table:
    source: T0.1.2
    output_port: table_arn
    transfer: memory
    required: true

interface:
  input: "Bucket ARN from T0.1.1, Table ARN from T0.1.2"
  output: "backend.tf file path"

output:
  location: file
  path: "/tmp/blueprint/T0.1.3/output.json"
  ports:
    backend_file:
      type: file_path

acceptance_criteria:
  - "backend.tf exists in infrastructure/terraform/"
  - "terraform init succeeds"
  - "State file created in S3"

verification:
  smoke:
    command: "test -f infrastructure/terraform/backend.tf"
    timeout: PT5S
  unit:
    command: "cd infrastructure/terraform && terraform init -reconfigure"
    timeout: PT2M

rollback: "rm -f infrastructure/terraform/backend.tf"

files_to_create:
  - infrastructure/terraform/backend.tf
```

---

### T0.2: DynamoDB Tables

```yaml
task_id: T0.2
name: "Create DynamoDB tables for tenant data"
status: not_started
dependencies: [T0.1]

input_bindings:
  backend:
    source: T0.1
    output_port: backend_config
    transfer: file
    required: true

interface:
  input: "Terraform backend configuration"
  output: "DynamoDB table ARNs for all tables"
  output_type: json
  output_schema:
    type: object
    properties:
      users_table_arn: { type: string }
      api_keys_table_arn: { type: string }
      jobs_table_arn: { type: string }
      usage_table_arn: { type: string }
    required: [users_table_arn, api_keys_table_arn, jobs_table_arn, usage_table_arn]

output:
  location: file
  path: "/tmp/blueprint/T0.2/output.json"
  ports:
    table_arns:
      type: json

acceptance_criteria:
  - "users table with user_id partition key"
  - "api_keys table with key_hash partition key, user_id GSI"
  - "jobs table with job_id partition key, user_id-status GSI"
  - "usage_events table with user_id partition key, timestamp sort key"
  - "All tables use on-demand billing (PAY_PER_REQUEST)"

verification:
  smoke:
    command: "aws dynamodb list-tables --profile soc --query 'TableNames' | grep -c outpost"
    timeout: PT15S
  unit:
    command: "cd infrastructure/terraform && terraform plan -target=module.dynamodb"
    timeout: PT2M

rollback: "cd infrastructure/terraform && terraform destroy -target=module.dynamodb -auto-approve"

resources:
  locks:
    - name: "terraform_state"
      mode: exclusive
    - name: "dynamodb_schema"
      mode: exclusive
```

#### T0.2.1: Users Table Schema

```yaml
task_id: T0.2.1
name: "Define users table Terraform module"
status: not_started
dependencies: [T0.1.3]

interface:
  input: "User data model requirements"
  output: "Terraform module for users table"

output:
  location: file
  path: "/tmp/blueprint/T0.2.1/output.json"
  ports:
    module_path:
      type: file_path

acceptance_criteria:
  - "Partition key: user_id (S)"
  - "Attributes: email, created_at, tier, stripe_customer_id"
  - "GSI: email-index (email -> user_id)"
  - "Billing mode: PAY_PER_REQUEST"
  - "Point-in-time recovery enabled"

verification:
  smoke:
    command: "test -f infrastructure/terraform/modules/dynamodb/users.tf"
    timeout: PT5S

rollback: "rm -f infrastructure/terraform/modules/dynamodb/users.tf"

files_to_create:
  - infrastructure/terraform/modules/dynamodb/users.tf
```

#### T0.2.2: API Keys Table Schema

```yaml
task_id: T0.2.2
name: "Define api_keys table Terraform module"
status: not_started
dependencies: [T0.1.3]

interface:
  input: "API key data model requirements"
  output: "Terraform module for api_keys table"

output:
  location: file
  path: "/tmp/blueprint/T0.2.2/output.json"
  ports:
    module_path:
      type: file_path

acceptance_criteria:
  - "Partition key: key_hash (S) — SHA-256 of full key"
  - "Attributes: user_id, key_prefix, environment, created_at, last_used_at, revoked_at"
  - "GSI: user_id-index (user_id -> key_hash)"
  - "Billing mode: PAY_PER_REQUEST"

verification:
  smoke:
    command: "test -f infrastructure/terraform/modules/dynamodb/api_keys.tf"
    timeout: PT5S

rollback: "rm -f infrastructure/terraform/modules/dynamodb/api_keys.tf"

files_to_create:
  - infrastructure/terraform/modules/dynamodb/api_keys.tf
```

#### T0.2.3: Jobs Table Schema

```yaml
task_id: T0.2.3
name: "Define jobs table Terraform module"
status: not_started
dependencies: [T0.1.3]

interface:
  input: "Job data model requirements"
  output: "Terraform module for jobs table"

output:
  location: file
  path: "/tmp/blueprint/T0.2.3/output.json"
  ports:
    module_path:
      type: file_path

acceptance_criteria:
  - "Partition key: job_id (S)"
  - "Sort key: none (single item per job)"
  - "Attributes: user_id, status, executor, repo, task, created_at, started_at, completed_at, output_url"
  - "GSI: user_id-status-index (user_id, status) for querying user's jobs by status"
  - "GSI: status-created_at-index (status, created_at) for queue polling"
  - "Billing mode: PAY_PER_REQUEST"
  - "TTL on completed jobs (90 days)"

verification:
  smoke:
    command: "test -f infrastructure/terraform/modules/dynamodb/jobs.tf"
    timeout: PT5S

rollback: "rm -f infrastructure/terraform/modules/dynamodb/jobs.tf"

files_to_create:
  - infrastructure/terraform/modules/dynamodb/jobs.tf
```

#### T0.2.4: Usage Events Table Schema

```yaml
task_id: T0.2.4
name: "Define usage_events table Terraform module"
status: not_started
dependencies: [T0.1.3]

interface:
  input: "Usage tracking data model"
  output: "Terraform module for usage_events table"

output:
  location: file
  path: "/tmp/blueprint/T0.2.4/output.json"
  ports:
    module_path:
      type: file_path

acceptance_criteria:
  - "Partition key: user_id (S)"
  - "Sort key: timestamp (S) — ISO 8601"
  - "Attributes: event_type, job_id, executor, duration_ms, api_key_prefix"
  - "Billing mode: PAY_PER_REQUEST"
  - "TTL: 365 days"

verification:
  smoke:
    command: "test -f infrastructure/terraform/modules/dynamodb/usage_events.tf"
    timeout: PT5S

rollback: "rm -f infrastructure/terraform/modules/dynamodb/usage_events.tf"

files_to_create:
  - infrastructure/terraform/modules/dynamodb/usage_events.tf
```

#### T0.2.5: Apply DynamoDB Terraform

```yaml
task_id: T0.2.5
name: "Apply DynamoDB Terraform configuration"
status: not_started
dependencies: [T0.2.1, T0.2.2, T0.2.3, T0.2.4]

interface:
  input: "All DynamoDB table modules"
  output: "Created table ARNs"

output:
  location: file
  path: "/tmp/blueprint/T0.2.5/output.json"
  ports:
    table_arns:
      type: json

acceptance_criteria:
  - "terraform apply succeeds"
  - "All 4 tables created in us-east-1"
  - "All tables show ACTIVE status"

verification:
  smoke:
    command: "aws dynamodb list-tables --profile soc --region us-east-1 | grep -c outpost"
    timeout: PT15S
  unit:
    command: "cd infrastructure/terraform && terraform output -json dynamodb_table_arns"
    timeout: PT30S

rollback: "cd infrastructure/terraform && terraform destroy -target=module.dynamodb -auto-approve"

resources:
  locks:
    - name: "terraform_state"
      mode: exclusive
```

---

### T0.3: Secrets Manager Configuration

```yaml
task_id: T0.3
name: "Configure AWS Secrets Manager for tenant credentials"
status: not_started
dependencies: [T0.1]

input_bindings:
  backend:
    source: T0.1
    output_port: backend_config
    transfer: file
    required: true

interface:
  input: "Terraform backend"
  output: "Secrets Manager ARN prefix for tenant secrets"

output:
  location: file
  path: "/tmp/blueprint/T0.3/output.json"
  ports:
    secrets_prefix:
      type: string

acceptance_criteria:
  - "Terraform module for Secrets Manager exists"
  - "IAM policy for secret access created"
  - "Secret naming convention: /outpost/tenants/{user_id}/{key_type}"

verification:
  smoke:
    command: "test -f infrastructure/terraform/modules/secrets/main.tf"
    timeout: PT5S

rollback: "rm -rf infrastructure/terraform/modules/secrets/"

files_to_create:
  - infrastructure/terraform/modules/secrets/main.tf
  - infrastructure/terraform/modules/secrets/variables.tf
  - infrastructure/terraform/modules/secrets/outputs.tf
  - infrastructure/terraform/modules/secrets/iam.tf
```

#### T0.3.1: Secrets Manager Terraform Module

```yaml
task_id: T0.3.1
name: "Create Secrets Manager Terraform module"
status: not_started
dependencies: [T0.1.3]

interface:
  input: "Secret naming convention and IAM requirements"
  output: "Terraform module files"

output:
  location: file
  path: "/tmp/blueprint/T0.3.1/output.json"
  ports:
    module_path:
      type: file_path

acceptance_criteria:
  - "Module creates IAM policy for Lambda/ECS secret access"
  - "Secret naming: /outpost/tenants/{user_id}/github_token"
  - "Secret naming: /outpost/tenants/{user_id}/anthropic_key"
  - "Secret naming: /outpost/tenants/{user_id}/openai_key"
  - "KMS encryption with customer-managed key"

verification:
  smoke:
    command: "test -f infrastructure/terraform/modules/secrets/main.tf"
    timeout: PT5S

rollback: "rm -rf infrastructure/terraform/modules/secrets/"

files_to_create:
  - infrastructure/terraform/modules/secrets/main.tf
  - infrastructure/terraform/modules/secrets/variables.tf
  - infrastructure/terraform/modules/secrets/outputs.tf
```

#### T0.3.2: Secrets IAM Policy

```yaml
task_id: T0.3.2
name: "Create IAM policy for secret access"
status: not_started
dependencies: [T0.3.1]

interface:
  input: "Secrets Manager module"
  output: "IAM policy ARN"

output:
  location: file
  path: "/tmp/blueprint/T0.3.2/output.json"
  ports:
    policy_arn:
      type: string

acceptance_criteria:
  - "Policy allows secretsmanager:GetSecretValue"
  - "Resource scoped to /outpost/tenants/* prefix"
  - "Condition restricts to specific ECS task role and Lambda role"

verification:
  smoke:
    command: "test -f infrastructure/terraform/modules/secrets/iam.tf"
    timeout: PT5S

rollback: "rm -f infrastructure/terraform/modules/secrets/iam.tf"

files_to_create:
  - infrastructure/terraform/modules/secrets/iam.tf
```

#### T0.3.3: Apply Secrets Manager Terraform

```yaml
task_id: T0.3.3
name: "Apply Secrets Manager Terraform configuration"
status: not_started
dependencies: [T0.3.1, T0.3.2]

interface:
  input: "Secrets Manager module"
  output: "Created resources"

output:
  location: file
  path: "/tmp/blueprint/T0.3.3/output.json"
  ports:
    kms_key_arn:
      type: string
    policy_arn:
      type: string

acceptance_criteria:
  - "KMS key created for secrets encryption"
  - "IAM policy attached"
  - "terraform apply succeeds"

verification:
  smoke:
    command: "cd infrastructure/terraform && terraform output -json secrets_kms_key_arn"
    timeout: PT30S

rollback: "cd infrastructure/terraform && terraform destroy -target=module.secrets -auto-approve"

resources:
  locks:
    - name: "terraform_state"
      mode: exclusive
```

---

## Tier 1: Authentication & API Layer

### T1.1: API Gateway Configuration

```yaml
task_id: T1.1
name: "Configure API Gateway with Lambda authorizer"
status: not_started
dependencies: [T0.2, T0.3]

input_bindings:
  tables:
    source: T0.2
    output_port: table_arns
    transfer: file
    required: true
  secrets:
    source: T0.3
    output_port: secrets_prefix
    transfer: file
    required: true

interface:
  input: "DynamoDB table ARNs, Secrets prefix"
  output: "API Gateway endpoint URL"
  output_type: json
  output_schema:
    type: object
    properties:
      api_url: { type: string }
      api_id: { type: string }
      stage: { type: string }
    required: [api_url, api_id]

output:
  location: file
  path: "/tmp/blueprint/T1.1/output.json"
  ports:
    api_endpoint:
      type: json

acceptance_criteria:
  - "API Gateway HTTP API created"
  - "Lambda authorizer attached to all routes"
  - "Routes: POST /v1/jobs, GET /v1/jobs, GET /v1/jobs/{id}, GET /v1/usage"
  - "CORS enabled for web console"
  - "Custom domain ready (optional)"

verification:
  smoke:
    command: "cd infrastructure/terraform && terraform output -json api_gateway_url"
    timeout: PT30S
  unit:
    command: "curl -s -o /dev/null -w '%{http_code}' $(terraform output -raw api_gateway_url)/health | grep 200"
    timeout: PT30S

rollback: "cd infrastructure/terraform && terraform destroy -target=module.api_gateway -auto-approve"
```

#### T1.1.1: Lambda Authorizer Function

```yaml
task_id: T1.1.1
name: "Create Lambda authorizer for API key validation"
status: not_started
dependencies: [T0.2.5]

interface:
  input: "DynamoDB api_keys table ARN"
  output: "Lambda function ARN"

output:
  location: file
  path: "/tmp/blueprint/T1.1.1/output.json"
  ports:
    lambda_arn:
      type: string

acceptance_criteria:
  - "Lambda function in Python 3.11"
  - "Validates op_live_xxx and op_test_xxx key formats"
  - "Looks up key_hash in DynamoDB api_keys table"
  - "Returns IAM policy with user_id in context"
  - "Updates last_used_at on successful auth"
  - "Rejects revoked keys"
  - "< 50ms cold start (use provisioned concurrency if needed)"

verification:
  smoke:
    command: "test -f src/outpost/functions/authorizer/handler.py"
    timeout: PT5S
  unit:
    command: "cd src && python -m pytest tests/unit/test_authorizer.py -v"
    timeout: PT2M

rollback: "rm -rf src/outpost/functions/authorizer/"

files_to_create:
  - src/outpost/functions/authorizer/handler.py
  - src/outpost/functions/authorizer/__init__.py
  - tests/unit/test_authorizer.py
```

#### T1.1.2: API Gateway Terraform Module

```yaml
task_id: T1.1.2
name: "Create API Gateway Terraform module"
status: not_started
dependencies: [T1.1.1]

interface:
  input: "Lambda authorizer ARN"
  output: "Terraform module files"

output:
  location: file
  path: "/tmp/blueprint/T1.1.2/output.json"
  ports:
    module_path:
      type: file_path

acceptance_criteria:
  - "HTTP API (not REST API) for cost efficiency"
  - "Lambda authorizer integration"
  - "Routes defined with OpenAPI spec"
  - "Throttling: 100 req/sec burst, 50 req/sec steady"
  - "Access logging to CloudWatch"

verification:
  smoke:
    command: "test -f infrastructure/terraform/modules/api_gateway/main.tf"
    timeout: PT5S

rollback: "rm -rf infrastructure/terraform/modules/api_gateway/"

files_to_create:
  - infrastructure/terraform/modules/api_gateway/main.tf
  - infrastructure/terraform/modules/api_gateway/routes.tf
  - infrastructure/terraform/modules/api_gateway/variables.tf
  - infrastructure/terraform/modules/api_gateway/outputs.tf
```

#### T1.1.3: API Route Handlers

```yaml
task_id: T1.1.3
name: "Create Lambda handlers for API routes"
status: not_started
dependencies: [T0.2.5]

interface:
  input: "DynamoDB table ARNs"
  output: "Lambda function ARNs for all routes"

output:
  location: file
  path: "/tmp/blueprint/T1.1.3/output.json"
  ports:
    lambda_arns:
      type: json

acceptance_criteria:
  - "POST /v1/jobs — Submit job to queue"
  - "GET /v1/jobs — List user's jobs (paginated)"
  - "GET /v1/jobs/{id} — Get job details"
  - "GET /v1/usage — Get usage statistics"
  - "All handlers validate input with Pydantic"
  - "All handlers log to CloudWatch with user_id"

verification:
  smoke:
    command: "test -f src/outpost/functions/api/jobs.py"
    timeout: PT5S
  unit:
    command: "cd src && python -m pytest tests/unit/test_api_handlers.py -v"
    timeout: PT2M

rollback: "rm -rf src/outpost/functions/api/"

files_to_create:
  - src/outpost/functions/api/jobs.py
  - src/outpost/functions/api/usage.py
  - src/outpost/functions/api/__init__.py
  - tests/unit/test_api_handlers.py
```

#### T1.1.4: Apply API Gateway Terraform

```yaml
task_id: T1.1.4
name: "Apply API Gateway Terraform and deploy Lambdas"
status: not_started
dependencies: [T1.1.1, T1.1.2, T1.1.3]

interface:
  input: "All Lambda functions and API Gateway module"
  output: "Deployed API endpoint"

output:
  location: file
  path: "/tmp/blueprint/T1.1.4/output.json"
  ports:
    api_url:
      type: string

acceptance_criteria:
  - "terraform apply succeeds"
  - "API Gateway endpoint accessible"
  - "Authorizer rejects invalid keys with 401"
  - "Health endpoint returns 200"

verification:
  smoke:
    command: "curl -s -o /dev/null -w '%{http_code}' $(cd infrastructure/terraform && terraform output -raw api_gateway_url)/health"
    timeout: PT30S
  integration:
    command: "cd tests && python -m pytest integration/test_api_gateway.py -v"
    timeout: PT5M

rollback: "cd infrastructure/terraform && terraform destroy -target=module.api_gateway -auto-approve"

resources:
  locks:
    - name: "terraform_state"
      mode: exclusive
```

---

### T1.2: Tenant Management API

```yaml
task_id: T1.2
name: "Implement tenant registration and API key management"
status: not_started
dependencies: [T1.1]

input_bindings:
  api:
    source: T1.1
    output_port: api_endpoint
    transfer: file
    required: true

interface:
  input: "API Gateway endpoint"
  output: "Tenant management endpoints"

output:
  location: file
  path: "/tmp/blueprint/T1.2/output.json"
  ports:
    endpoints:
      type: json

acceptance_criteria:
  - "POST /v1/auth/register — Create new tenant"
  - "POST /v1/auth/api-keys — Generate new API key"
  - "GET /v1/auth/api-keys — List user's API keys (masked)"
  - "DELETE /v1/auth/api-keys/{id} — Revoke API key"
  - "API key format: op_live_XXXX or op_test_XXXX"
  - "Keys stored as SHA-256 hash in DynamoDB"

verification:
  smoke:
    command: "test -f src/outpost/functions/api/auth.py"
    timeout: PT5S
  unit:
    command: "cd src && python -m pytest tests/unit/test_auth.py -v"
    timeout: PT2M

rollback: "rm -f src/outpost/functions/api/auth.py"

files_to_create:
  - src/outpost/functions/api/auth.py
  - tests/unit/test_auth.py
```

#### T1.2.1: User Registration Handler

```yaml
task_id: T1.2.1
name: "Implement user registration endpoint"
status: not_started
dependencies: [T0.2.5]

interface:
  input: "Email, password (or OAuth)"
  output: "User ID and initial API key"

output:
  location: file
  path: "/tmp/blueprint/T1.2.1/output.json"
  ports:
    handler_path:
      type: file_path

acceptance_criteria:
  - "Validates email format"
  - "Creates user record in DynamoDB"
  - "Generates initial API key"
  - "Sets default tier to 'free'"
  - "Returns user_id and masked API key"

verification:
  smoke:
    command: "grep -q 'def register' src/outpost/functions/api/auth.py"
    timeout: PT5S

rollback: "git checkout src/outpost/functions/api/auth.py"
```

#### T1.2.2: API Key Generation

```yaml
task_id: T1.2.2
name: "Implement API key generation and storage"
status: not_started
dependencies: [T0.2.5]

interface:
  input: "User ID, environment (live/test)"
  output: "Generated API key (shown once)"

output:
  location: file
  path: "/tmp/blueprint/T1.2.2/output.json"
  ports:
    handler_path:
      type: file_path

acceptance_criteria:
  - "Generate cryptographically secure 32-byte key"
  - "Format: op_{env}_{base64_key}"
  - "Store SHA-256 hash in DynamoDB (never raw key)"
  - "Store key_prefix for display (op_live_abc123...)"
  - "Return full key only once at creation"

verification:
  smoke:
    command: "grep -q 'def generate_api_key' src/outpost/functions/api/auth.py"
    timeout: PT5S

rollback: "git checkout src/outpost/functions/api/auth.py"
```

#### T1.2.3: API Key Revocation

```yaml
task_id: T1.2.3
name: "Implement API key revocation"
status: not_started
dependencies: [T1.2.2]

interface:
  input: "API key ID, user ID"
  output: "Revocation confirmation"

output:
  location: file
  path: "/tmp/blueprint/T1.2.3/output.json"
  ports:
    handler_path:
      type: file_path

acceptance_criteria:
  - "Verify key belongs to requesting user"
  - "Set revoked_at timestamp"
  - "Authorizer rejects revoked keys immediately"
  - "Key remains in database for audit trail"

verification:
  smoke:
    command: "grep -q 'def revoke_api_key' src/outpost/functions/api/auth.py"
    timeout: PT5S

rollback: "git checkout src/outpost/functions/api/auth.py"
```

---

## Tier 2: Job Queue & Worker Pool

### T2.1: SQS Queue Configuration

```yaml
task_id: T2.1
name: "Create SQS queues with priority lanes"
status: not_started
dependencies: [T0.1]

input_bindings:
  backend:
    source: T0.1
    output_port: backend_config
    transfer: file
    required: true

interface:
  input: "Terraform backend"
  output: "SQS queue URLs and ARNs"
  output_type: json
  output_schema:
    type: object
    properties:
      free_queue_url: { type: string }
      pro_queue_url: { type: string }
      enterprise_queue_url: { type: string }
      dlq_url: { type: string }
    required: [free_queue_url, pro_queue_url, dlq_url]

output:
  location: file
  path: "/tmp/blueprint/T2.1/output.json"
  ports:
    queue_urls:
      type: json

acceptance_criteria:
  - "3 priority queues: outpost-jobs-free, outpost-jobs-pro, outpost-jobs-enterprise"
  - "1 dead letter queue: outpost-jobs-dlq"
  - "Visibility timeout: 5 minutes"
  - "Message retention: 14 days"
  - "DLQ receives after 3 failed attempts"
  - "Long polling enabled (20 seconds)"

verification:
  smoke:
    command: "aws sqs list-queues --profile soc --queue-name-prefix outpost-jobs | grep -c outpost"
    timeout: PT15S

rollback: "cd infrastructure/terraform && terraform destroy -target=module.sqs -auto-approve"

files_to_create:
  - infrastructure/terraform/modules/sqs/main.tf
  - infrastructure/terraform/modules/sqs/variables.tf
  - infrastructure/terraform/modules/sqs/outputs.tf
```

#### T2.1.1: SQS Terraform Module

```yaml
task_id: T2.1.1
name: "Create SQS Terraform module"
status: not_started
dependencies: [T0.1.3]

interface:
  input: "Queue requirements"
  output: "Terraform module files"

output:
  location: file
  path: "/tmp/blueprint/T2.1.1/output.json"
  ports:
    module_path:
      type: file_path

acceptance_criteria:
  - "Standard queues (not FIFO) for cost efficiency"
  - "Server-side encryption with AWS-managed key"
  - "Redrive policy to DLQ after 3 failures"
  - "IAM policy for Lambda/ECS access"

verification:
  smoke:
    command: "test -f infrastructure/terraform/modules/sqs/main.tf"
    timeout: PT5S

rollback: "rm -rf infrastructure/terraform/modules/sqs/"

files_to_create:
  - infrastructure/terraform/modules/sqs/main.tf
  - infrastructure/terraform/modules/sqs/variables.tf
  - infrastructure/terraform/modules/sqs/outputs.tf
```

#### T2.1.2: Apply SQS Terraform

```yaml
task_id: T2.1.2
name: "Apply SQS Terraform configuration"
status: not_started
dependencies: [T2.1.1]

interface:
  input: "SQS module"
  output: "Created queue URLs"

output:
  location: file
  path: "/tmp/blueprint/T2.1.2/output.json"
  ports:
    queue_urls:
      type: json

acceptance_criteria:
  - "terraform apply succeeds"
  - "All 4 queues created"
  - "Queues accessible from Lambda and ECS"

verification:
  smoke:
    command: "aws sqs get-queue-url --profile soc --queue-name outpost-jobs-pro"
    timeout: PT15S

rollback: "cd infrastructure/terraform && terraform destroy -target=module.sqs -auto-approve"

resources:
  locks:
    - name: "terraform_state"
      mode: exclusive
```

---

### T2.2: ECS Fargate Worker

```yaml
task_id: T2.2
name: "Create ECS Fargate task definition and service"
status: not_started
dependencies: [T2.1, T0.3]

input_bindings:
  queues:
    source: T2.1
    output_port: queue_urls
    transfer: file
    required: true
  secrets:
    source: T0.3
    output_port: secrets_prefix
    transfer: file
    required: true

interface:
  input: "SQS queue URLs, Secrets Manager prefix"
  output: "ECS cluster ARN, service ARN"
  output_type: json
  output_schema:
    type: object
    properties:
      cluster_arn: { type: string }
      service_arn: { type: string }
      task_definition_arn: { type: string }
    required: [cluster_arn, service_arn, task_definition_arn]

output:
  location: file
  path: "/tmp/blueprint/T2.2/output.json"
  ports:
    ecs_resources:
      type: json

acceptance_criteria:
  - "ECS cluster: outpost-workers"
  - "Task definition with worker container"
  - "Service with desired count = 0 (scale from zero)"
  - "Task size: 0.5 vCPU, 1GB RAM"
  - "Spot capacity provider for cost savings"
  - "CloudWatch logging enabled"

verification:
  smoke:
    command: "aws ecs describe-clusters --profile soc --clusters outpost-workers --query 'clusters[0].status' --output text | grep ACTIVE"
    timeout: PT30S

rollback: "cd infrastructure/terraform && terraform destroy -target=module.ecs -auto-approve"
```

#### T2.2.1: Worker Docker Image

```yaml
task_id: T2.2.1
name: "Create worker Docker image with all agent CLIs"
status: not_started
dependencies: []

interface:
  input: "Agent CLI requirements"
  output: "Docker image name and tag"

output:
  location: file
  path: "/tmp/blueprint/T2.2.1/output.json"
  ports:
    image_uri:
      type: string

acceptance_criteria:
  - "Base: Ubuntu 24.04"
  - "Includes: Python 3.12, Node.js 20, Git"
  - "Claude Code CLI installed"
  - "Codex CLI installed"
  - "Gemini CLI installed"
  - "Aider installed with DeepSeek support"
  - "Grok agent script included"
  - "dispatch-unified.sh copied and executable"
  - "Image size < 2GB"
  - "Non-root user for execution"

verification:
  smoke:
    command: "docker build -t outpost-worker:test -f infrastructure/docker/worker/Dockerfile ."
    timeout: PT10M
  unit:
    command: "docker run --rm outpost-worker:test claude --version"
    timeout: PT30S

rollback: "docker rmi outpost-worker:test"

files_to_create:
  - infrastructure/docker/worker/Dockerfile
  - infrastructure/docker/worker/entrypoint.sh
  - infrastructure/docker/worker/requirements.txt
```

#### T2.2.2: ECR Repository

```yaml
task_id: T2.2.2
name: "Create ECR repository for worker image"
status: not_started
dependencies: [T0.1.3]

interface:
  input: "Terraform backend"
  output: "ECR repository URI"

output:
  location: file
  path: "/tmp/blueprint/T2.2.2/output.json"
  ports:
    repository_uri:
      type: string

acceptance_criteria:
  - "Repository: outpost-worker"
  - "Image scanning enabled"
  - "Lifecycle policy: keep last 10 images"
  - "Immutable tags enabled"

verification:
  smoke:
    command: "aws ecr describe-repositories --profile soc --repository-names outpost-worker"
    timeout: PT15S

rollback: "aws ecr delete-repository --profile soc --repository-name outpost-worker --force"

files_to_create:
  - infrastructure/terraform/modules/ecr/main.tf
```

#### T2.2.3: Push Worker Image to ECR

```yaml
task_id: T2.2.3
name: "Build and push worker image to ECR"
status: not_started
dependencies: [T2.2.1, T2.2.2]

interface:
  input: "Dockerfile, ECR repository URI"
  output: "Pushed image URI with tag"

output:
  location: file
  path: "/tmp/blueprint/T2.2.3/output.json"
  ports:
    image_uri:
      type: string

acceptance_criteria:
  - "Image built successfully"
  - "Image pushed to ECR"
  - "Image tagged with git SHA and 'latest'"
  - "Vulnerability scan passes (no critical)"

verification:
  smoke:
    command: "aws ecr describe-images --profile soc --repository-name outpost-worker --image-ids imageTag=latest"
    timeout: PT30S

rollback: "aws ecr batch-delete-image --profile soc --repository-name outpost-worker --image-ids imageTag=latest"

resources:
  locks:
    - name: "ecr_push"
      mode: exclusive
```

#### T2.2.4: ECS Task Definition

```yaml
task_id: T2.2.4
name: "Create ECS Fargate task definition"
status: not_started
dependencies: [T2.2.3]

interface:
  input: "Worker image URI, Secrets Manager ARNs"
  output: "Task definition ARN"

output:
  location: file
  path: "/tmp/blueprint/T2.2.4/output.json"
  ports:
    task_definition_arn:
      type: string

acceptance_criteria:
  - "Fargate launch type"
  - "CPU: 512 (0.5 vCPU), Memory: 1024 (1GB)"
  - "Task role with SQS, DynamoDB, Secrets Manager, S3 access"
  - "Execution role for ECR pull and CloudWatch logs"
  - "Environment variables for queue URLs"
  - "Secrets from Secrets Manager"
  - "Log driver: awslogs"

verification:
  smoke:
    command: "aws ecs describe-task-definition --profile soc --task-definition outpost-worker --query 'taskDefinition.status' --output text"
    timeout: PT15S

rollback: "aws ecs deregister-task-definition --profile soc --task-definition outpost-worker:1"

files_to_create:
  - infrastructure/terraform/modules/ecs/task_definition.tf
```

#### T2.2.5: ECS Service with Auto-Scaling

```yaml
task_id: T2.2.5
name: "Create ECS service with scale-to-zero auto-scaling"
status: not_started
dependencies: [T2.2.4, T2.1.2]

interface:
  input: "Task definition ARN, SQS queue ARNs"
  output: "ECS service ARN"

output:
  location: file
  path: "/tmp/blueprint/T2.2.5/output.json"
  ports:
    service_arn:
      type: string

acceptance_criteria:
  - "Service: outpost-worker-service"
  - "Desired count: 0 (starts scaled to zero)"
  - "Minimum: 0, Maximum: 20"
  - "Auto-scaling based on SQS ApproximateNumberOfMessages"
  - "Scale up: 1 task per 5 messages"
  - "Scale down: after 5 minutes of no messages"
  - "Spot capacity provider (70% spot, 30% on-demand)"
  - "Deployment circuit breaker enabled"

verification:
  smoke:
    command: "aws ecs describe-services --profile soc --cluster outpost-workers --services outpost-worker-service --query 'services[0].status' --output text | grep ACTIVE"
    timeout: PT30S
  unit:
    command: "aws application-autoscaling describe-scalable-targets --profile soc --service-namespace ecs --resource-ids service/outpost-workers/outpost-worker-service"
    timeout: PT15S

rollback: "aws ecs update-service --profile soc --cluster outpost-workers --service outpost-worker-service --desired-count 0 && aws ecs delete-service --profile soc --cluster outpost-workers --service outpost-worker-service --force"

files_to_create:
  - infrastructure/terraform/modules/ecs/service.tf
  - infrastructure/terraform/modules/autoscaling/main.tf
```

---

### T2.3: Worker Implementation

```yaml
task_id: T2.3
name: "Implement SQS worker that processes jobs"
status: not_started
dependencies: [T2.2]

input_bindings:
  ecs:
    source: T2.2
    output_port: ecs_resources
    transfer: file
    required: true

interface:
  input: "ECS resources"
  output: "Worker Python module"

output:
  location: file
  path: "/tmp/blueprint/T2.3/output.json"
  ports:
    worker_path:
      type: file_path

acceptance_criteria:
  - "Polls all 3 priority queues (enterprise first, then pro, then free)"
  - "Retrieves tenant secrets from Secrets Manager"
  - "Clones repo to isolated workspace"
  - "Invokes dispatch-unified.sh with tenant credentials"
  - "Uploads output to S3"
  - "Updates job status in DynamoDB"
  - "Deletes message on success, returns to queue on failure"
  - "Graceful shutdown on SIGTERM"

verification:
  smoke:
    command: "test -f src/outpost/worker/main.py"
    timeout: PT5S
  unit:
    command: "cd src && python -m pytest tests/unit/test_worker.py -v"
    timeout: PT3M

rollback: "rm -rf src/outpost/worker/"

files_to_create:
  - src/outpost/worker/main.py
  - src/outpost/worker/executor.py
  - src/outpost/worker/secrets.py
  - tests/unit/test_worker.py
```

#### T2.3.1: SQS Polling Logic

```yaml
task_id: T2.3.1
name: "Implement SQS polling with priority ordering"
status: not_started
dependencies: [T2.1.2]

interface:
  input: "SQS queue URLs"
  output: "Polling module"

output:
  location: file
  path: "/tmp/blueprint/T2.3.1/output.json"
  ports:
    module_path:
      type: file_path

acceptance_criteria:
  - "Long polling (20 seconds)"
  - "Priority order: enterprise > pro > free"
  - "Batch size: 1 (for workspace isolation)"
  - "Visibility timeout extension for long jobs"
  - "Exponential backoff on empty queues"

verification:
  smoke:
    command: "grep -q 'def poll_queues' src/outpost/worker/main.py"
    timeout: PT5S

rollback: "git checkout src/outpost/worker/main.py"
```

#### T2.3.2: Job Executor

```yaml
task_id: T2.3.2
name: "Implement job execution with workspace isolation"
status: not_started
dependencies: [T2.3.1]

interface:
  input: "Job message from SQS"
  output: "Execution result"

output:
  location: file
  path: "/tmp/blueprint/T2.3.2/output.json"
  ports:
    module_path:
      type: file_path

acceptance_criteria:
  - "Creates isolated workspace: /workspace/{user_id}-{job_id}/"
  - "Clones repo with tenant's GitHub PAT"
  - "Injects tenant API keys as environment variables"
  - "Runs dispatch-unified.sh"
  - "Captures stdout/stderr"
  - "Uploads artifacts to S3: s3://outpost-artifacts/{user_id}/{job_id}/"
  - "Cleans up workspace on completion"
  - "Timeout: configurable per tier (free: 5min, pro: 15min, enterprise: 60min)"

verification:
  smoke:
    command: "grep -q 'def execute_job' src/outpost/worker/executor.py"
    timeout: PT5S

rollback: "git checkout src/outpost/worker/executor.py"
```

#### T2.3.3: S3 Artifact Storage

```yaml
task_id: T2.3.3
name: "Implement S3 artifact upload and presigned URLs"
status: not_started
dependencies: [T0.1.3]

interface:
  input: "Terraform backend"
  output: "S3 bucket and module"

output:
  location: file
  path: "/tmp/blueprint/T2.3.3/output.json"
  ports:
    bucket_name:
      type: string

acceptance_criteria:
  - "Bucket: outpost-artifacts-{account_id}"
  - "Lifecycle: 90-day expiration for completed jobs"
  - "Server-side encryption"
  - "Presigned URLs for download (1-hour expiry)"
  - "CORS for web console access"

verification:
  smoke:
    command: "aws s3 ls s3://outpost-artifacts-311493921645 --profile soc"
    timeout: PT15S

rollback: "aws s3 rb s3://outpost-artifacts-311493921645 --force --profile soc"

files_to_create:
  - infrastructure/terraform/modules/s3/main.tf
```

---

## Tier 3: Billing & Usage Tracking

### T3.1: Stripe Integration

```yaml
task_id: T3.1
name: "Integrate Stripe for subscription billing"
status: not_started
dependencies: [T1.2]

input_bindings:
  auth:
    source: T1.2
    output_port: endpoints
    transfer: file
    required: true

interface:
  input: "Auth endpoints"
  output: "Stripe webhook handler and billing endpoints"

output:
  location: file
  path: "/tmp/blueprint/T3.1/output.json"
  ports:
    stripe_endpoints:
      type: json

acceptance_criteria:
  - "Stripe products: Free, Pro ($29/mo), Enterprise (custom)"
  - "POST /v1/billing/subscribe — Create subscription"
  - "POST /v1/billing/portal — Redirect to Stripe portal"
  - "POST /v1/webhooks/stripe — Handle subscription events"
  - "Updates user tier on subscription change"
  - "Webhook signature verification"

verification:
  smoke:
    command: "test -f src/outpost/functions/api/billing.py"
    timeout: PT5S
  unit:
    command: "cd src && python -m pytest tests/unit/test_billing.py -v"
    timeout: PT2M

rollback: "rm -f src/outpost/functions/api/billing.py"

files_to_create:
  - src/outpost/functions/api/billing.py
  - src/outpost/functions/api/webhooks.py
  - src/outpost/services/stripe_client.py
  - tests/unit/test_billing.py
```

#### T3.1.1: Stripe Product Configuration

```yaml
task_id: T3.1.1
name: "Configure Stripe products and prices"
status: not_started
dependencies: []

interface:
  input: "Tier structure"
  output: "Stripe product and price IDs"

output:
  location: file
  path: "/tmp/blueprint/T3.1.1/output.json"
  ports:
    stripe_ids:
      type: json

acceptance_criteria:
  - "Product: Outpost Pro"
  - "Price: $29/month recurring"
  - "Product: Outpost Enterprise"
  - "Price: Custom (contact sales)"
  - "Free tier has no Stripe product"
  - "Price IDs stored in SSM Parameter Store"

verification:
  smoke:
    command: "aws ssm get-parameter --profile soc --name /outpost/prod/stripe_pro_price_id --query 'Parameter.Value' --output text"
    timeout: PT15S

rollback: "aws ssm delete-parameter --profile soc --name /outpost/prod/stripe_pro_price_id"
```

#### T3.1.2: Subscription Handler

```yaml
task_id: T3.1.2
name: "Implement subscription creation endpoint"
status: not_started
dependencies: [T3.1.1]

interface:
  input: "User ID, tier selection"
  output: "Stripe checkout session URL"

output:
  location: file
  path: "/tmp/blueprint/T3.1.2/output.json"
  ports:
    handler_path:
      type: file_path

acceptance_criteria:
  - "Creates Stripe checkout session"
  - "Passes user_id in metadata"
  - "Redirects to success/cancel URLs"
  - "Handles upgrade/downgrade"

verification:
  smoke:
    command: "grep -q 'def create_subscription' src/outpost/functions/api/billing.py"
    timeout: PT5S

rollback: "git checkout src/outpost/functions/api/billing.py"
```

#### T3.1.3: Webhook Handler

```yaml
task_id: T3.1.3
name: "Implement Stripe webhook handler"
status: not_started
dependencies: [T3.1.1]

interface:
  input: "Stripe webhook events"
  output: "User tier updates"

output:
  location: file
  path: "/tmp/blueprint/T3.1.3/output.json"
  ports:
    handler_path:
      type: file_path

acceptance_criteria:
  - "Verifies webhook signature"
  - "Handles: checkout.session.completed"
  - "Handles: customer.subscription.updated"
  - "Handles: customer.subscription.deleted"
  - "Updates user tier in DynamoDB"
  - "Returns 200 quickly (async processing)"

verification:
  smoke:
    command: "grep -q 'def handle_webhook' src/outpost/functions/api/webhooks.py"
    timeout: PT5S

rollback: "git checkout src/outpost/functions/api/webhooks.py"
```

---

### T3.2: Usage Metering & Quotas

```yaml
task_id: T3.2
name: "Implement usage tracking and quota enforcement"
status: not_started
dependencies: [T2.3, T3.1]

input_bindings:
  worker:
    source: T2.3
    output_port: worker_path
    transfer: file
    required: true
  billing:
    source: T3.1
    output_port: stripe_endpoints
    transfer: file
    required: true

interface:
  input: "Worker module, Billing endpoints"
  output: "Usage tracking module"

output:
  location: file
  path: "/tmp/blueprint/T3.2/output.json"
  ports:
    metering_module:
      type: file_path

acceptance_criteria:
  - "Records usage event on job completion"
  - "Tracks: job_count, total_duration, executor_usage"
  - "Enforces daily quotas: Free=10, Pro=100, Enterprise=unlimited"
  - "Returns 429 when quota exceeded"
  - "Quota resets daily at midnight UTC"
  - "GET /v1/usage returns current period usage"

verification:
  smoke:
    command: "test -f src/outpost/services/metering.py"
    timeout: PT5S
  unit:
    command: "cd src && python -m pytest tests/unit/test_metering.py -v"
    timeout: PT2M

rollback: "rm -f src/outpost/services/metering.py"

files_to_create:
  - src/outpost/services/metering.py
  - tests/unit/test_metering.py
```

#### T3.2.1: Usage Event Recording

```yaml
task_id: T3.2.1
name: "Implement usage event recording"
status: not_started
dependencies: [T0.2.4]

interface:
  input: "Job completion event"
  output: "Usage event in DynamoDB"

output:
  location: file
  path: "/tmp/blueprint/T3.2.1/output.json"
  ports:
    module_path:
      type: file_path

acceptance_criteria:
  - "Records: user_id, timestamp, job_id, executor, duration_ms"
  - "Atomic increment of daily counter"
  - "Uses DynamoDB conditional writes"

verification:
  smoke:
    command: "grep -q 'def record_usage' src/outpost/services/metering.py"
    timeout: PT5S

rollback: "git checkout src/outpost/services/metering.py"
```

#### T3.2.2: Quota Enforcement

```yaml
task_id: T3.2.2
name: "Implement quota checking in job submission"
status: not_started
dependencies: [T3.2.1]

interface:
  input: "User tier, current usage"
  output: "Allow/deny decision"

output:
  location: file
  path: "/tmp/blueprint/T3.2.2/output.json"
  ports:
    module_path:
      type: file_path

acceptance_criteria:
  - "Checks usage before job submission"
  - "Returns 429 with retry-after header when over quota"
  - "Includes usage stats in error response"
  - "Enterprise tier bypasses quota check"

verification:
  smoke:
    command: "grep -q 'def check_quota' src/outpost/services/metering.py"
    timeout: PT5S

rollback: "git checkout src/outpost/services/metering.py"
```

#### T3.2.3: Usage API Endpoint

```yaml
task_id: T3.2.3
name: "Implement usage statistics endpoint"
status: not_started
dependencies: [T3.2.1]

interface:
  input: "User ID, date range"
  output: "Usage statistics"

output:
  location: file
  path: "/tmp/blueprint/T3.2.3/output.json"
  ports:
    handler_path:
      type: file_path

acceptance_criteria:
  - "GET /v1/usage returns current period stats"
  - "Includes: jobs_today, jobs_remaining, tier, quota_resets_at"
  - "Optional: historical usage by date range"

verification:
  smoke:
    command: "grep -q 'def get_usage' src/outpost/functions/api/usage.py"
    timeout: PT5S

rollback: "git checkout src/outpost/functions/api/usage.py"
```

---

## Tier 4: Testing & Deployment

### T4.1: Integration Tests

```yaml
task_id: T4.1
name: "Create integration test suite"
status: not_started
dependencies: [T3.2]

input_bindings:
  all_modules:
    source: T3.2
    output_port: metering_module
    transfer: file
    required: true

interface:
  input: "All implemented modules"
  output: "Passing integration tests"

output:
  location: file
  path: "/tmp/blueprint/T4.1/output.json"
  ports:
    test_results:
      type: json

acceptance_criteria:
  - "End-to-end: Register user → Get API key → Submit job → Poll status → Get results"
  - "Quota enforcement: Exceed quota → 429 response"
  - "Multi-tenant isolation: User A cannot access User B's jobs"
  - "Scale-to-zero verification: No workers when queue empty"
  - "Scale-up verification: Workers spawn when jobs submitted"

verification:
  smoke:
    command: "test -d tests/integration/"
    timeout: PT5S
  integration:
    command: "cd tests && python -m pytest integration/ -v --tb=short"
    timeout: PT15M

rollback: "rm -rf tests/integration/"

files_to_create:
  - tests/integration/test_e2e_flow.py
  - tests/integration/test_quota_enforcement.py
  - tests/integration/test_multi_tenant.py
  - tests/integration/test_auto_scaling.py
  - tests/integration/conftest.py
```

#### T4.1.1: E2E Flow Test

```yaml
task_id: T4.1.1
name: "Create end-to-end flow integration test"
status: not_started
dependencies: [T1.2, T2.3]

interface:
  input: "API endpoints"
  output: "Passing E2E test"

output:
  location: file
  path: "/tmp/blueprint/T4.1.1/output.json"
  ports:
    test_path:
      type: file_path

acceptance_criteria:
  - "Creates test user"
  - "Generates API key"
  - "Submits job to test repo"
  - "Polls until completion"
  - "Verifies output artifact exists"
  - "Cleans up test data"

verification:
  smoke:
    command: "test -f tests/integration/test_e2e_flow.py"
    timeout: PT5S

rollback: "rm -f tests/integration/test_e2e_flow.py"
```

#### T4.1.2: Multi-Tenant Isolation Test

```yaml
task_id: T4.1.2
name: "Create multi-tenant isolation test"
status: not_started
dependencies: [T1.2]

interface:
  input: "API endpoints"
  output: "Passing isolation test"

output:
  location: file
  path: "/tmp/blueprint/T4.1.2/output.json"
  ports:
    test_path:
      type: file_path

acceptance_criteria:
  - "Creates two test users"
  - "User A submits job"
  - "User B cannot GET User A's job"
  - "User B cannot access User A's artifacts"
  - "API keys are user-scoped"

verification:
  smoke:
    command: "test -f tests/integration/test_multi_tenant.py"
    timeout: PT5S

rollback: "rm -f tests/integration/test_multi_tenant.py"
```

#### T4.1.3: Auto-Scaling Test

```yaml
task_id: T4.1.3
name: "Create auto-scaling verification test"
status: not_started
dependencies: [T2.2.5]

interface:
  input: "ECS service, SQS queues"
  output: "Passing scaling test"

output:
  location: file
  path: "/tmp/blueprint/T4.1.3/output.json"
  ports:
    test_path:
      type: file_path

acceptance_criteria:
  - "Verifies desired count = 0 when queue empty"
  - "Submits 5 jobs"
  - "Verifies workers scale up within 60 seconds"
  - "Jobs complete"
  - "Verifies workers scale down to 0 after idle period"

verification:
  smoke:
    command: "test -f tests/integration/test_auto_scaling.py"
    timeout: PT5S

rollback: "rm -f tests/integration/test_auto_scaling.py"
```

---

### T4.2: Production Deployment

```yaml
task_id: T4.2
name: "Deploy to production with terraform apply"
status: not_started
dependencies: [T4.1]

input_bindings:
  tests:
    source: T4.1
    output_port: test_results
    transfer: file
    required: true

interface:
  input: "Passing integration tests"
  output: "Production deployment"

output:
  location: file
  path: "/tmp/blueprint/T4.2/output.json"
  ports:
    deployment:
      type: json

acceptance_criteria:
  - "terraform plan shows expected changes"
  - "terraform apply succeeds"
  - "API Gateway endpoint accessible"
  - "Health check returns 200"
  - "No workers running (scale-to-zero verified)"
  - "All CloudWatch alarms in OK state"

verification:
  smoke:
    command: "curl -s -o /dev/null -w '%{http_code}' $(cd infrastructure/terraform && terraform output -raw api_gateway_url)/health | grep 200"
    timeout: PT30S
  integration:
    command: "cd tests && python -m pytest integration/test_e2e_flow.py -v"
    timeout: PT10M

rollback: "cd infrastructure/terraform && terraform destroy -auto-approve"

human_required:
  action: "Approve production deployment"
  reason: "Final review before applying infrastructure changes"
  timeout: PT1H
  on_timeout: abort

resources:
  locks:
    - name: "terraform_state"
      mode: exclusive
```

#### T4.2.1: Terraform Plan Review

```yaml
task_id: T4.2.1
name: "Generate and review Terraform plan"
status: not_started
dependencies: [T4.1]

interface:
  input: "All Terraform modules"
  output: "Terraform plan output"

output:
  location: file
  path: "/tmp/blueprint/T4.2.1/output.json"
  ports:
    plan_file:
      type: file_path

acceptance_criteria:
  - "terraform plan succeeds"
  - "No unexpected resource deletions"
  - "Cost estimate < $50/month (idle scenario)"

verification:
  smoke:
    command: "cd infrastructure/terraform && terraform plan -out=tfplan"
    timeout: PT5M

rollback: "rm -f infrastructure/terraform/tfplan"

human_required:
  action: "Review Terraform plan output"
  reason: "Ensure no unexpected changes before apply"
  timeout: PT1H
  on_timeout: abort
```

#### T4.2.2: Apply Terraform

```yaml
task_id: T4.2.2
name: "Apply Terraform configuration"
status: not_started
dependencies: [T4.2.1]

interface:
  input: "Approved Terraform plan"
  output: "Deployed resources"

output:
  location: file
  path: "/tmp/blueprint/T4.2.2/output.json"
  ports:
    outputs:
      type: json

acceptance_criteria:
  - "terraform apply succeeds"
  - "All resources created"
  - "Outputs captured: API URL, cluster ARN, etc."

verification:
  smoke:
    command: "cd infrastructure/terraform && terraform output -json"
    timeout: PT30S

rollback: "cd infrastructure/terraform && terraform destroy -auto-approve"

resources:
  locks:
    - name: "terraform_state"
      mode: exclusive
```

#### T4.2.3: Post-Deployment Verification

```yaml
task_id: T4.2.3
name: "Verify production deployment"
status: not_started
dependencies: [T4.2.2]

interface:
  input: "Deployed resources"
  output: "Verification report"

output:
  location: file
  path: "/tmp/blueprint/T4.2.3/output.json"
  ports:
    verification_report:
      type: json

acceptance_criteria:
  - "API Gateway health check returns 200"
  - "DynamoDB tables accessible"
  - "SQS queues exist"
  - "ECS cluster active with 0 running tasks"
  - "CloudWatch log groups created"
  - "No critical CloudWatch alarms"

verification:
  smoke:
    command: "curl -s $(cd infrastructure/terraform && terraform output -raw api_gateway_url)/health"
    timeout: PT30S
  unit:
    command: "aws ecs describe-clusters --profile soc --clusters outpost-workers --query 'clusters[0].runningTasksCount' --output text | grep 0"
    timeout: PT15S

rollback: "echo 'Manual investigation required'"
```

---

## Dependency Graph

```yaml
dependency_graph:
  # Tier 0
  T0.1:
    depends_on: []
  T0.1.1:
    depends_on: []
  T0.1.2:
    depends_on: [T0.1.1]
  T0.1.3:
    depends_on: [T0.1.1, T0.1.2]
  T0.2:
    depends_on: [T0.1]
  T0.2.1:
    depends_on: [T0.1.3]
  T0.2.2:
    depends_on: [T0.1.3]
  T0.2.3:
    depends_on: [T0.1.3]
  T0.2.4:
    depends_on: [T0.1.3]
  T0.2.5:
    depends_on: [T0.2.1, T0.2.2, T0.2.3, T0.2.4]
  T0.3:
    depends_on: [T0.1]
  T0.3.1:
    depends_on: [T0.1.3]
  T0.3.2:
    depends_on: [T0.3.1]
  T0.3.3:
    depends_on: [T0.3.1, T0.3.2]

  # Tier 1
  T1.1:
    depends_on: [T0.2, T0.3]
  T1.1.1:
    depends_on: [T0.2.5]
  T1.1.2:
    depends_on: [T1.1.1]
  T1.1.3:
    depends_on: [T0.2.5]
  T1.1.4:
    depends_on: [T1.1.1, T1.1.2, T1.1.3]
  T1.2:
    depends_on: [T1.1]
  T1.2.1:
    depends_on: [T0.2.5]
  T1.2.2:
    depends_on: [T0.2.5]
  T1.2.3:
    depends_on: [T1.2.2]

  # Tier 2
  T2.1:
    depends_on: [T0.1]
  T2.1.1:
    depends_on: [T0.1.3]
  T2.1.2:
    depends_on: [T2.1.1]
  T2.2:
    depends_on: [T2.1, T0.3]
  T2.2.1:
    depends_on: []
  T2.2.2:
    depends_on: [T0.1.3]
  T2.2.3:
    depends_on: [T2.2.1, T2.2.2]
  T2.2.4:
    depends_on: [T2.2.3]
  T2.2.5:
    depends_on: [T2.2.4, T2.1.2]
  T2.3:
    depends_on: [T2.2]
  T2.3.1:
    depends_on: [T2.1.2]
  T2.3.2:
    depends_on: [T2.3.1]
  T2.3.3:
    depends_on: [T0.1.3]

  # Tier 3
  T3.1:
    depends_on: [T1.2]
  T3.1.1:
    depends_on: []
  T3.1.2:
    depends_on: [T3.1.1]
  T3.1.3:
    depends_on: [T3.1.1]
  T3.2:
    depends_on: [T2.3, T3.1]
  T3.2.1:
    depends_on: [T0.2.4]
  T3.2.2:
    depends_on: [T3.2.1]
  T3.2.3:
    depends_on: [T3.2.1]

  # Tier 4
  T4.1:
    depends_on: [T3.2]
  T4.1.1:
    depends_on: [T1.2, T2.3]
  T4.1.2:
    depends_on: [T1.2]
  T4.1.3:
    depends_on: [T2.2.5]
  T4.2:
    depends_on: [T4.1]
  T4.2.1:
    depends_on: [T4.1]
  T4.2.2:
    depends_on: [T4.2.1]
  T4.2.3:
    depends_on: [T4.2.2]
```

---

## Visual Dependency Graph

```
Tier 0: Foundation
T0.1.1 ──► T0.1.2 ──► T0.1.3 ──┬──► T0.2.1 ─┐
                               ├──► T0.2.2 ─┼──► T0.2.5
                               ├──► T0.2.3 ─┤
                               ├──► T0.2.4 ─┘
                               ├──► T0.3.1 ──► T0.3.2 ──► T0.3.3
                               └──► T2.1.1 ──► T2.1.2

Tier 1: Auth & API
T0.2.5 ──┬──► T1.1.1 ──► T1.1.2 ─┐
         ├──► T1.1.3 ────────────┼──► T1.1.4 ──► T1.2
         └──► T1.2.1                             │
              T1.2.2 ──► T1.2.3 ◄────────────────┘

Tier 2: Queue & Workers
T2.1.2 ──┬──► T2.3.1 ──► T2.3.2
         └──► T2.2.5 ◄── T2.2.4 ◄── T2.2.3 ◄── T2.2.1 + T2.2.2

Tier 3: Billing & Metering
T3.1.1 ──┬──► T3.1.2
         └──► T3.1.3 ──► T3.2 ◄── T3.2.1 ──┬──► T3.2.2
                                           └──► T3.2.3

Tier 4: Testing & Deployment
T3.2 ──► T4.1 ──┬──► T4.1.1
                ├──► T4.1.2
                └──► T4.1.3 ──► T4.2.1 ──► T4.2.2 ──► T4.2.3
```

---

## Cost Estimate (Idle vs Active)

| Component | Idle (no jobs) | 100 jobs/day | 1000 jobs/day |
|-----------|---------------|--------------|---------------|
| API Gateway | $0 | $1 | $5 |
| Lambda | $0 | $2 | $10 |
| DynamoDB | $1 | $5 | $25 |
| SQS | $0 | $0.50 | $2 |
| ECS Fargate | **$0** | $30 | $150 |
| Secrets Manager | $1 | $2 | $5 |
| S3 | $1 | $3 | $15 |
| CloudWatch | $2 | $5 | $20 |
| **Total** | **~$5/mo** | **~$48/mo** | **~$232/mo** |

**Critical:** Fargate is $0 when no tasks running. Scale-to-zero is enforced.

---

## Document Control

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0.0 | 2026-01-11 | Claude Opus 4.5 | Initial depth=3 blueprint |

---

*Outpost V2 Multi-Tenant SaaS Blueprint — Generated 2026-01-11*
*"Pay-per-use infrastructure with scale-to-zero economics"*
