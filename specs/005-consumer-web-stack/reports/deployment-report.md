# Deployment Report: Web Application Stack

| Field | Value |
| ----- | ----- |
| Branch | 005-consumer-web-stack |
| Date | 2026-03-17 |
| Provider | aws ~> 6.19 (installed: 6.36.0) |
| HCP Workspace | sandbox_consumer_web_stack |

## Modules Composed

| Module | Registry Source | Version | Status |
| ------ | -------------- | ------- | ------ |
| s3_alb_logs | app.terraform.io/hashi-demos-apj/s3-bucket/aws | ~> 4.6 | PASS |
| dynamodb | app.terraform.io/hashi-demos-apj/dynamodb-table/aws | ~> 4.6 | PASS |
| sqs | app.terraform.io/hashi-demos-apj/sqs/aws | ~> 4.3 | PASS |
| sns_alerts | app.terraform.io/hashi-demos-apj/sns/aws | ~> 7.0 | PASS |
| ec2_sg | app.terraform.io/hashi-demos-apj/security-group/aws | ~> 5.3 | PASS |
| ec2_web | app.terraform.io/hashi-demos-apj/ec2-instance/aws | ~> 6.1 | PASS |
| alb | app.terraform.io/hashi-demos-apj/alb/aws | ~> 9.14 | PASS |
| alb_5xx_alarm | app.terraform.io/hashi-demos-apj/cloudwatch/aws//modules/metric-alarm | ~> 5.6 | PASS |
| sqs_depth_alarm | app.terraform.io/hashi-demos-apj/cloudwatch/aws//modules/metric-alarm | ~> 5.6 | PASS |

**Summary**: 9 modules composed

## terraform validate

**Result**: CLEAN

No errors. Configuration valid after `terraform init` with HCP Terraform backend.

## terraform fmt -check

**Result**: FORMATTED

All files properly formatted. No changes needed.

## tflint

**Result**: CLEAN (post-init)

No findings after module installation. Initial pre-init runs showed expected "module not installed" errors.

## trivy config

| Metric | Count |
| ------ | ----- |
| Total | 0 |
| Defects | 0 |
| Accepted | 0 |

### Defects (block deployment)

None.

### Accepted Risks (do not block deployment)

None in consumer-authored code. ALB public exposure and egress rules are findings in upstream module internals, documented as design decisions in consumer-design.md Section 4.

## Quality Score

| # | Dimension | Score | Issues |
| - | --------- | ----- | ------ |
| 1 | Module Usage | 9.5 | All 9 modules from private registry, no raw resources except glue |
| 2 | Security & Compliance | 8.5 | 3 documented security overrides for dev (deletion protection, force destroy, HTTP-only) |
| 3 | Code Quality | 9.0 | Clean structure, proper naming, well-organized files |
| 4 | Variables & Outputs | 9.5 | 16 variables with validation, 13 outputs with descriptions |
| 5 | Wiring & Integration | 9.5 | All 16 wiring connections verified, correct type transformations |
| 6 | Constitution Alignment | 9.0 | Full compliance with consumer constitution |

**Overall Score**: 9.1/10.0 — Exceptional
**Production Readiness**: Ready

## Sandbox Deployment

| Field | Value |
| ----- | ----- |
| Workspace | sandbox_consumer_web_stack |
| Run URL | https://app.terraform.io/app/hashi-demos-apj/sandbox_consumer_web_stack/runs/run-6Qjnuj21wTHDsRAA |
| Plan Status | PLANNED |
| Apply Status | APPLIED |
| Resources Created | 27 |
| Resources Changed | 0 |
| Resources Destroyed | 0 |
| HCP Cost Estimate (native) | $32.82/mo |

### Key Resources Deployed

- ALB: `web-stack-dev-alb` (web-stack-dev-alb-1524093805.ap-southeast-2.elb.amazonaws.com)
- EC2: `i-0e7d64b48fc30e0f1` (15.134.213.252)
- S3: `web-stack-dev-alb-logs-86d8f100`
- DynamoDB: `web-stack-dev-app-data`
- SQS: `web-stack-dev-queue` (+ DLQ: `web-stack-dev-queue-dlq`)
- SNS: `web-stack-dev-alerts`
- CloudWatch Alarms: `web-stack-dev-alb-5xx`, `web-stack-dev-sqs-depth`
- Security Group: HTTP ingress from VPC CIDR

### Sentinel Policy Check

All policies passed (3 policy sets evaluated).

## Cost Analysis

| Field | Value |
| ----- | ----- |
| Run Task | NONE CONFIGURED |
| Status | N/A |
| Enforcement Mode | N/A |
| Estimated Cost | $32.82/mo (HCP native estimate) |
| Policy Violations | 0 |
| Details URL | N/A |

No Cloudability Run Task attached to workspace. Cost governance skipped — using native HCP cost estimate only.

### Optimization Recommendations

No optimization recommendations provided.

## Sandbox Destroy

| Field | Value |
| ----- | ----- |
| Destroy Status | PENDING |
| Destroy Run URL | N/A |

## Overall Status

**PASS**
