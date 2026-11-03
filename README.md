# Azure SQL CI/CD accelerator

A private-network-first GitHub template for passwordless Azure SQL releases.
Start from a new private repository, run guided setup, and deploy reviewed SQL
changes through GitHub Actions. No SQL passwords or client secrets.

## Architecture

```text
PR -> GitHub-hosted validation and DACPAC build (no Azure permissions)
main -> immutable database-release artifact -> dev environment
                                               |
                                  dedicated private Linux runner
                                               |
                                  repository-specific GitHub OIDC
                                               |
                                  Entra token -> SQL private endpoint
                                               |
                                  deploy DACPAC -> rollback smoke tests

Manual promotion -> validate successful dev job + exact unexpired artifact ID
                 -> production environment -> separate deployment identity
                 -> same DACPAC and scripts, no rebuild -> rollback smoke tests
```

The runner has no public IP, no attached Azure identity, and denies all inbound
traffic. NAT provides outbound access. SQL is Entra-only with public access
disabled. Deployment identities receive resource-group Reader plus explicit
contained-user grants, not SQL administrator or `db_owner`.

## Quick start

1. Use this template to create a **new private repository**, clone it, and open
   [the VS Code workspace](Azure%20SQL%20CI-CD%20Accelerator.code-workspace).
   Keep the default branch named `main`.
2. Install PowerShell 7.4+, .NET SDK 10, Azure CLI with Bicep, GitHub CLI,
   Git and OpenSSH. Authenticate with `az login` and `gh auth login`.
3. Copy the configuration and replace every placeholder:

   ```powershell
   Copy-Item config\setup.example.json config\setup.json
   ```

4. Review [setup permissions and prerequisites](docs/SETUP.md), choose a **new
   isolated resource group**, and preview:

   ```powershell
   .\scripts\Setup-Accelerator.ps1
   ```

5. Review the what-if and [ongoing costs](docs/COST-AND-CLEANUP.md), then opt in:

   ```powershell
   .\scripts\Setup-Accelerator.ps1 -Apply
   ```

Setup provisions SQL and private networking, initializes the runner, bootstraps
SQL users, configures GitHub environments/variables and verifies real OIDC login,
private SQL connectivity and grants in **both** environments. Deployments remain
disabled until all readiness jobs succeed. Rerun with the same configuration
after correcting a failure.

## Working with the accelerator

- [Setup and reruns](docs/SETUP.md)
- [Releases, permissions and operations](docs/OPERATIONS.md)
- [Costs and isolated cleanup](docs/COST-AND-CLEANUP.md)
- [Validation and fresh-repository acceptance](docs/VALIDATION.md)
- [MIT license](LICENSE)

Local validation (does not deploy anything):

```powershell
.\scripts\Test-Accelerator.ps1
```

Change [the SQL project](database/Database.sqlproj) through a PR. After setup,
merging to `main` deploys dev. Dispatch **Promote verified database to production**
with the successful dev run ID to reuse its exact artifact.

## Scope and honest status

This is a generalized accelerator derived from a working private demonstration,
not a replacement for that baseline. Its historical deployment evidence is
**not** proof that a fresh accelerator environment passed.

Version 1 supports **GitHub.com private repositories and Azure public cloud**,
fixed `dev`/`production` environment names, Ubuntu 24.04 x64 and one persistent
dedicated runner. Names, region, repository, identities, databases and network
ranges are adopter-specific. The two Basic databases and shared runner are
starter sizing, not a highly available production architecture.

Protect `main`, restrict repository write access and configure production
reviewers where your GitHub plan permits. A manual dispatch alone is not
two-person approval. Deploy-to-Azure buttons are intentionally omitted:
infrastructure provisioning is only one part of CI/CD onboarding.
