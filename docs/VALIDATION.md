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
Failure-path tests also cover preserved rerun metadata, simultaneous execution
and cleanup errors, Azure deletion failures, checkpointed GitHub cleanup retries,
replacement runners, and mismatched cleanup targets without calling live services.
Run Command tests also cover oversized scripts/tokens, short CLI arguments,
owner-only request-file permissions, provisioning waits, exact protected parameter
values and temporary-file cleanup, including simultaneous local/remote cleanup failures.

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

On November 9, 2026, maintainer review confirmed the
[November 4 readiness run](https://github.com/rayxfelipe/azure-sql-cicd-accelerator/actions/runs/41915540588)
explicitly passed `OIDC (dev)`, `OIDC (production)`, `SQL (dev)` and
`SQL (production)`. This is live OIDC/private SQL readiness evidence, not proof
of a DACPAC deployment, a fresh customer repository, rerun recovery or cleanup.
No production promotion run was present at that review. The README quick start
now provides the customer-executed dev/PR/production acceptance path; passing its
documentation checks is not a claim that those live releases have been run.

Quick-start documentation checks on November 9 passed: 25 relative file/heading
links resolved, 16 PowerShell example blocks parsed, and both SQL example
insertions parsed in their actual source locations. An isolated copy of the SQL
project containing the documented `CustomerNote` column built with zero warnings
and errors. No provisioning, PR, dev deployment or production promotion was
executed by these documentation checks.

Windows setup recovery checks on November 9 passed: all 99 regression tests,
the DACPAC build, PowerShell/SQL/JSON checks, and Bicep compilation/topology
invariants. A live file-backed request through Windows `az.cmd` executed a
21,173-character script with a 20,000-character synthetic protected value on
the isolated trial runner. The temporary Run Command was removed afterward;
no SQL grants, schema, setup state or release gates were changed by this probe.
Guest DNS checks also resolved SQL inside the configured private-endpoint subnet.
These checks verify the command-line transport fix, not a complete setup rerun
or a successful dev/production release.

## Maintainer source verification

Verified November 2, 2026:

| Check | Result |
|---|---|
| Accelerator regression tests | 82 passed, including preserved rerun metadata, cleanup ordering/retries, exact runner IDs, and primary/secondary failure reporting. |
| DACPAC build | Succeeded; zero warnings/errors. |
| PowerShell, workspace/config JSON and readiness/smoke SQL syntax | Passed. |
| Full Bicep compilation and compiled private-network/Entra invariants | Passed, exit 0. |
| Three workflows with actionlint 1.7.12; runner Bash syntax | Passed, exit 0. |
| Fresh clone from the private accelerator repository | Local validation passed; no baseline metadata or local state packaged. |
| [Initial hosted credential-free CI](https://github.com/rayxfelipe/azure-sql-cicd-accelerator/actions/runs/41568749901) | Build passed; dev deployment was skipped because setup is incomplete. |
| Baseline | Original revision and clean working tree retained unchanged. |
| Checkov | Not installed; no Checkov scan is claimed. |
| Live readiness (subsequent November 4 run) | Both OIDC and both private SQL readiness jobs passed; see the linked evidence above. |
| Initial setup provisioning path / live DACPAC releases / end-to-end adoption | Not established by readiness alone. Complete the isolated customer walkthrough and record its actual release, rerun and cleanup evidence. |
