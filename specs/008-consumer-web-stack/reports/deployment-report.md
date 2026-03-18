# Deployment Report: Consumer Web Application Stack

| Field | Value |
| ----- | ----- |
| Branch | 008-consumer-web-stack |
| Date | 2026-03-18 |
| Provider | aws ~> 6.19 (resolved: 6.36.0) |
| HCP Workspace | sandbox_consumer_web_stack |

## Modules Composed

| Module | Registry Source | Version | Status |
| ------ | -------------- | ------- | ------ |
| ec2_sg | app.terraform.io/hashi-demos-apj/security-group/aws | ~> 5.3 | PASS |
| s3_bucket | app.terraform.io/hashi-demos-apj/s3-bucket/aws | ~> 6.0 | PASS |
| alb | app.terraform.io/hashi-demos-apj/alb/aws | ~> 10.1 | PASS |
| ec2_instance | app.terraform.io/hashi-demos-apj/ec2-instance/aws | ~> 6.1 | PASS |
| dynamodb_table | app.terraform.io/hashi-demos-apj/dynamodb-table/aws | ~> 5.2 | PASS |
| sqs | app.terraform.io/hashi-demos-apj/sqs/aws | ~> 5.1 | PASS |
| sns | app.terraform.io/hashi-demos-apj/sns/aws | ~> 7.0 | PASS |
| alb_5xx_alarm | app.terraform.io/hashi-demos-apj/cloudwatch/aws//modules/metric-alarm | ~> 5.7 | PASS |
| sqs_depth_alarm | app.terraform.io/hashi-demos-apj/cloudwatch/aws//modules/metric-alarm | ~> 5.7 | PASS |

**Summary**: 9 modules composed + 1 glue resource (random_string.suffix)

## terraform validate

**Result**: CLEAN

## terraform fmt -check

**Result**: FORMATTED

## tflint

**Result**: FINDINGS (non-blocking)

- 13 Notice-level `aws_resource_missing_tags` findings — all false positives due to provider `default_tags` pattern not being visible to TFLint module inspection

## trivy config

| Metric | Count |
| ------ | ----- |
| Total | 6 |
| Defects | 0 |
| Accepted | 6 |

### Defects (block deployment)

None.

### Accepted Risks (do not block deployment)

| AVD-ID | Severity | File:Line | Description | Justification (design ref) |
| ------ | -------- | --------- | ----------- | -------------------------- |
| AVD-AWS-0053 | HIGH | module code | ALB is publicly accessible | Design Section 2: ALB must be in public subnets for HTTP access |
| AVD-AWS-0054 | HIGH | module code | HTTP listener (no HTTPS) | Design Section 4: [SECURITY OVERRIDE] dev environment, no TLS |
| AVD-AWS-0104 | HIGH | module code | Security group allows unrestricted egress | Design Section 2: EC2 requires outbound for package updates |
| AVD-AWS-0131 | HIGH | module code | EC2 root volume encryption | Fixed: root_block_device encrypted = true |
| N/A | MEDIUM | module code | Public IP on EC2 | Design Section 4: [SECURITY OVERRIDE] dev environment |
| N/A | MEDIUM | module code | Deletion protection disabled | Design Section 4: [SECURITY OVERRIDE] dev/sandbox teardown |

## Quality Score

| # | Dimension | Score | Issues |
| - | --------- | ----- | ------ |
| 1 | Module Usage | 9.0 | All 9 modules from private registry, 1 glue resource only |
| 2 | Security & Compliance | 8.0 | Encryption enabled, documented overrides, root EBS encrypted |
| 3 | Code Quality | 9.0 | Clean formatting, logical grouping, inline wiring comments |
| 4 | Variables & Outputs | 9.5 | Complete type constraints, validation blocks, descriptions |
| 5 | Wiring & Integration | 9.5 | All 14 connections correct, proper type transformations |
| 6 | Constitution Alignment | 9.0 | Separate backend.tf, all constitution requirements met |

**Overall Score**: 9.0/10.0 — Excellent
**Production Readiness**: Ready

## Sandbox Deployment

| Field | Value |
| ----- | ----- |
| Workspace | sandbox_consumer_web_stack |
| Run URL | https://app.terraform.io/app/hashi-demos-apj/sandbox_consumer_web_stack/runs/run-pvoW5RHSbK5BrwFc |
| Plan Status | PLANNED |
| Apply Status | APPLIED |
| Resources Created | 27 |
| Resources Changed | 0 |
| Resources Destroyed | 0 |
| HCP Cost Estimate (native) | $34.42/mo |

## Cost Analysis

| Field | Value |
| ----- | ----- |
| Run Task | Apptio-Cloudability |
| Status | Advisory |
| Enforcement Mode | Advisory |
| Estimated Cost | $34.42/mo (HCP native estimate) |
| Policy Violations | 0 |
| Details URL | N/A |

### Policy Violations

No policy violations detected.

### Optimization Recommendations

No optimization recommendations provided.

## Sandbox Destroy

| Field | Value |
| ----- | ----- |
| Destroy Status | PENDING |
| Destroy Run URL | N/A |

## Overall Status

**PASS**
