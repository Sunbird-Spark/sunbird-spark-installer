# Security Policy

## Supported versions

| Branch | Role | Supported |
|---|---|---|
| `main` | Current released version | Yes |
| `v1.x.x` (e.g. `v1.1.1`) | Development branch for the next release; merged into `main` when released | Yes — fixes land here first |
| Older release tags (`spark-v1.0.x` and earlier) | Superseded | No — please upgrade to the latest `main` |

## Reporting a vulnerability

**Please do not open a public issue for security problems.**

Report privately using GitHub's private vulnerability reporting:

> https://github.com/Sunbird-Spark/sunbird-spark-installer/security/advisories/new

Include, where you can:

- the affected file(s) or component (e.g. a Helm chart, OpenTofu module, workflow or script),
- the branch or commit you tested against,
- steps to reproduce or a proof of concept,
- the impact you believe it has.

If private reporting is unavailable to you, open an issue titled **"Security contact request"** with no technical details, and a maintainer will arrange a private channel.

## What to expect

| Stage | Target |
|---|---|
| Acknowledgement | within 3 business days |
| Initial assessment and severity | within 10 business days |
| Fix or mitigation for High / Critical issues | as soon as practical; we will keep you informed of progress |
| Public disclosure | coordinated with the reporter once a fix is available, normally within 90 days of the report |

We will credit reporters in the release notes unless you ask us not to.

## Scope

This policy covers the contents of this repository: infrastructure-as-code, Helm charts and values, gateway and ingress configuration, CI/CD workflows, container image definitions and operational scripts.

Vulnerabilities in the **deployed application services** (knowledge-platform, lern-service, the portal, mobile app, etc.) should be reported to their own repositories. Vulnerabilities in **third-party components** (Keycloak, Kong, YugabyteDB, OpenSearch, Kafka, Redis, Grafana, etc.) should be reported upstream; if this repository's configuration makes such an issue worse, please tell us as well.

## Secrets

Never commit real credentials. The templates use `REPLACE_WITH_*` placeholders; populated `global-values.yaml`, `tf.sh`, `*.pem` and `*.key` files must stay out of version control. This repository runs GitGuardian `ggshield` as a pre-commit hook and GitHub secret scanning with push protection.
