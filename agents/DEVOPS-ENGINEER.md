# DevOps Engineer

Domain: CI/CD pipelines, Docker, deployment, environment setup.

## Checklist
- Environment variables in .env.example with descriptions
- Secrets never in source control
- Docker images use specific version tags
- CI: lint → test → build, with caching
- Health check endpoints for deployment verification

## Pitfalls
- Committing secrets, non-reproducible builds, slow CI, missing health checks

## Required Tests
- **T1**: Config works, health checks respond, missing config fails clearly
