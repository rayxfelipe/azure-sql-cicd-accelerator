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
against all workflows. The hosted **Publication checks** workflow separately
installs pinned scanners and checks history, workflows and compiled infrastructure
without Azure sign-in. Its [documented preview baseline](../SECURITY.md#infrastructure-preview-exceptions)
is not a clean raw policy scan. Local validation does not install these scanners;
do not claim a security scan was performed just because Bicep compiled.
SQL smoke/readiness scripts require an actual private Azure SQL
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

## Fresh-repository walkthrough: November 9, 2026

The maintainer completed the quick start in a separate private template-created
repository and isolated Azure environment. The initial attempt exposed the
Windows command-line limit; setup subsequently completed with the same
configuration after applying the
[transport fix](https://github.com/rayxfelipe/azure-sql-cicd-accelerator/commit/89f1cb21e72db3e18eb188167b3914c307af40a3).
This is successful adoption after a documented fix, not an untouched first-attempt
success. Evidence links below require access to the private trial repository;
adopters do not need that access to use the accelerator.

| Acceptance check | Evidence / result |
|---|---|
| Guided setup | [Setup verification](https://github.com/rayxfelipe/azure-sql-cicd-trial/actions/runs/42710120497) succeeded after the unchanged-configuration recovery. |
| Initial dev schema release | [Manual dev run](https://github.com/rayxfelipe/azure-sql-cicd-trial/actions/runs/42714443544) succeeded. |
| Additive schema PR | [Trial PR](https://github.com/rayxfelipe/azure-sql-cicd-trial/pull/1) added the nullable `CustomerNote` column and its smoke assertion; [PR validation](https://github.com/rayxfelipe/azure-sql-cicd-trial/actions/runs/42717123856) passed `build` and skipped `deploy-dev`. |
| Post-merge dev release | [Dev run `42717303020`](https://github.com/rayxfelipe/azure-sql-cicd-trial/actions/runs/42717303020) passed `build`, `deploy-dev` and SQL smoke tests at commit `462987d193a577c110746f869f6f506666c0b5fa`. |
| Production promotion | [Production run](https://github.com/rayxfelipe/azure-sql-cicd-trial/actions/runs/42718185335) passed trusted-source validation and exact-dev-artifact deployment, including production SQL smoke tests. |
| Immutable artifact | Dev run `42717303020` published `database-release`, artifact ID `13717823037`; production downloaded from that same source run through the validated artifact-ID path. |

This establishes the Windows happy path through fresh-repository onboarding,
schema-change review and production promotion. It does **not** complete the
clean already-completed-setup rerun, VM deallocate/start recovery, live negative
promotion tests, or cleanup/recreation acceptance checks. Those remain separate
release gates. Artifacts expire after 14 days; retain these links as dated
evidence, not as indefinitely reusable production inputs.

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

## Publication hardening: November 9, 2026

The distribution repository was detached from deployment: its setup gate is
false, its runner was unregistered, its environment deployment variables were
removed, and its readiness/promotion workflows were disabled. Only the two
source-owned Azure federations were revoked. No Azure resource group, VM,
database or identity was deleted; retained resources can still incur charges.
The successful trial repository and its deployment trust were preserved.
These source settings are not automatically copied to template-created repositories.

| Check | Result / boundary |
|---|---|
| `.\scripts\Test-Accelerator.ps1` | Passed all 99 regressions, PowerShell/SQL/JSON checks, DACPAC build with zero warnings/errors, and Bicep/private-topology checks. |
| `actionlint` 1.7.12 | All four workflows passed after immutable Node 24 Action upgrades. |
| `gitleaks git . --log-opts=--all --redact --no-banner` 8.30.1 | All 14 pre-hardening commits passed. The staged hardening content is scanned separately before commit, and hosted checks scan the resulting complete history. |
| Changed documentation | Relative file/heading links and PowerShell examples passed. |
| Checkov 3.4.3, raw ARM | 16 passed, 10 failed, zero skipped/parsing errors, 18 resource expressions. Not a clean policy scan. |
| Checkov with reviewed baseline | Zero new failures, ten explicitly skipped findings, zero parsing errors, 18 resource expressions. See the [exact preview dispositions](../SECURITY.md#infrastructure-preview-exceptions). |
| Negative policy probe | Changing only the compiled SQL TLS minimum to `1.0` produced non-baselined `CKV_AZURE_52` and exit 1. The source template was not changed. |
| NuGet package audit | The SQL MSBuild SDK exposes no ordinary PackageReference graph. Public-feed auditing also hit a local TLS handshake error; this is not clean SDK/bundled-library dependency evidence. Hosted auditing explicitly reports the coverage gap. |
| Dependency maintenance | Weekly Dependabot Action updates, immutable Action commits, read-only default workflow token and vulnerability alerts; vendor/bundled-tool advisory review remains necessary. |

The preview release notes record the exact hosted checks used for tagging.
Build and publication checks must pass, with source `deploy-dev` skipped.
Hosted compilation/scanning does not repeat the successful Azure walkthrough
using the newly upgraded deployment Actions.

Before wider customer use, complete the remaining setup-rerun, VM recovery,
live negative-promotion and cleanup/recreation acceptance checks in a disposable
environment. Review the documented infrastructure exceptions and bundled-tool
dependencies against the intended customer security policy. The repository
remains private until a separate publication decision; a preview tag is not GA.
