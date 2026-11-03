# Validation and acceptance

## Local, no deployment

```powershell
.\scripts\Test-Accelerator.ps1
```

This validates PowerShell syntax and workspace/configuration JSON; runs
regression tests for adopter naming/networks, isolation, trusted promotion,
explicit readiness evidence and protected Run Command cleanup; builds the SQL
project with warnings treated as errors; and compiles the full Bicep topology.
It also parses readiness/smoke SQL using the SQL project's existing ScriptDom
dependency and checks private-network/Entra controls in the compiled ARM template.

For workflow syntax/expression validation, run [actionlint](https://github.com/rhysd/actionlint)
against all three workflows. Optional infrastructure security scanners such as
Checkov are not bundled; do not claim a security scan was performed just because
Bicep compiled. SQL smoke/readiness scripts require an actual private Azure SQL
environment; local compilation does not execute those tests.

## Fresh-repository acceptance (separate Azure environment)

Do not reuse the baseline repository, OIDC identities, resource group or runner.

1. Create a fresh private repository from the template and clone it.
2. Run local validation. Verify its initial CI build succeeds with no Azure
   variables; `deploy-dev` must be **skipped**.
3. Configure a new dedicated Azure environment. Preview and apply guided setup.
4. Verify setup records successful `OIDC (dev)`, `OIDC (production)`,
   `SQL (dev)` and `SQL (production)` jobs before enabling releases.
5. Rerun setup unchanged. Check no duplicate resources/users/runners and no
   weakened production protection rules.
6. Dispatch main-branch Database CI to publish the initial schema; require dev
   smoke tests to pass.
7. Open an additive schema-change PR. Confirm build passes, deployment is skipped
   and the private runner is not used by the PR.
8. Merge to main. Verify dev publication and rollback smoke tests.
9. Dispatch production promotion using that dev run. Record source commit,
   source run, artifact ID and passing production smoke tests.
10. Negative tests: reject a PR run ID, skipped-dev run, failed run, foreign
    repository run, invalid run ID and expired/missing artifact.
11. Confirm SQL is Entra-only/public-disabled, endpoint connection approved,
    DNS resolves inside the configured subnet, VM has no public IP/identity,
    inbound NSG denies all, and deployment identities are not administrators.
12. Test cleanup against only this fresh environment; verify its group and runner
    registration disappear while the baseline remains untouched.

Record actual links/results in your adoption evidence. The original demonstration
was verified separately; that history is not transferable acceptance evidence.

## Current verification boundary

Repository/source validation is distinct from live adoption. Creating this
accelerator does not automatically provision Azure, run SQL smoke tests or prove
fresh-repository deployment. Complete the checklist above before claiming
end-to-end adoption.

## Maintainer source verification

Verified November 2, 2026:

| Check | Result |
|---|---|
| Accelerator regression tests | 44 passed, including isolation, promotion, readiness, active-release guards and Run Command cleanup. |
| DACPAC build | Succeeded; zero warnings/errors. |
| PowerShell, workspace/config JSON and readiness/smoke SQL syntax | Passed. |
| Full Bicep compilation and compiled private-network/Entra invariants | Passed, exit 0. |
| Three workflows with actionlint 1.7.12; runner Bash syntax | Passed, exit 0. |
| Fresh clone from the private accelerator repository | Local validation passed; no baseline metadata or local state packaged. |
| [Hosted credential-free CI](https://github.com/rayxfelipe/azure-sql-cicd-accelerator/actions/runs/41568749901) | Build passed; dev deployment was skipped because setup is incomplete. |
| Baseline | Original revision and clean working tree retained unchanged. |
| Checkov | Not installed; no Checkov scan is claimed. |
| New Azure provisioning / live SQL deployment / end-to-end adoption | Not executed. Requires an isolated adopter environment and explicit setup apply. |
