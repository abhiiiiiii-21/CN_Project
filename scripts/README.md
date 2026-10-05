# Operational Scripts

This directory contains shell automation scripts for certificate provisioning, configuration rendering, and automated demonstration workflows.

---

## Script Overview

| Script | Purpose |
|---|---|
| `make-certs.sh` | Generates a team Certificate Authority (CA) and issues TLS certificates with SAN for `app.TEAM.test` and `api.TEAM.test`. |
| `render-configs.sh` | Reads environment variables from `cn-team.env` and renders template files from `config/` into `config/live/`. |
| `demo.sh` | Runs test and verification flows for DNS resolution, HTTP/HTTPS connectivity, load balancing verification, and caching behavior. |

---

## Status

All scripts are currently stubbed with TODO comments. Implementation will occur in subsequent project phases.
