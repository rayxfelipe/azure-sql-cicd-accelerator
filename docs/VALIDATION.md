# Validate your deployment

Use this guide to check your own private deployment repository and Azure
environment. Start with the [quick start](../README.md#quick-start), then
[understand the resources](DEPLOYMENT-OUTCOME.md).
Source checks, successful setup and successful releases are different milestones.

## 1. Validate locally

From your repository root in PowerShell 7:

```powershell
.\scripts\Test-Accelerator.ps1
```

**Expected:** all regression tests pass, the DACPAC builds with zero warnings
or errors, and PowerShell/SQL/JSON checks plus Bicep/private-network checks pass.
No Azure provisioning or live SQL tests are performed.

In GitHub, `build` validates the source and **Publication checks** separately
scans history, workflows and compiled infrastructure without Azure sign-in.
Local validation does not run those scanners. Policy exceptions and bundled-tool
dependency coverage gaps remain documented in the [security policy](../SECURITY.md);
a green check is not a security certification.

## 2. Verify setup readiness

After [guided setup](SETUP.md#preview-and-apply), confirm:

- [ ] Setup printed `Setup verified`.
- [ ] `OIDC (dev)`, `OIDC (production)`, `SQL (dev)` and `SQL (production)`
  all explicitly succeeded in the linked verification run.
- [ ] The private runner is idle/online and the configured setup gate is complete.

A green workflow with skipped readiness jobs does not count. Setup verifies
identity, private connectivity and deployment grants; it does not publish the
sample schema. Never manually enable setup gates after a failure.
Use [setup recovery](SETUP.md#reruns-and-failures) instead.

## 3. Verify the release path

Follow [quick start steps 6-8](../README.md#6-deploy-the-initial-schema-to-dev)
in your own private repository. Check job and smoke-test results, not just
the workflow's overall status.

| Check | Expected result |
|---|---|
| Before setup | `build` passes without Azure variables; `deploy-dev` is skipped. |
| Initial dev release | `build`, `deploy-dev` and SQL smoke tests succeed. |
| Additive schema PR | `build` passes on GitHub-hosted runners; `deploy-dev` is skipped and the private runner is not used. |
| Merge to `main` | Dev deployment and smoke tests, including the new column assertion, succeed. |
| Production promotion | `validate-source`, `deploy-production` and production smoke tests succeed, using the exact artifact from that successful dev run without rebuilding. |

Save your repository revision, run URLs, source commit, dev run ID and promoted
artifact ID. Artifacts expire after 14 days; retain identifiers as dated evidence,
not indefinitely reusable promotion inputs. Your environment must pass these
checks independently; the maintainer's trial results are not transferable.

## Fresh-repository acceptance (separate Azure environment)

Before wider use, complete these checks in an isolated adoption environment.
Use a new repository, resource group, identities and runner, never a shared
or reference deployment. Keep the runner online during live tests.

- [ ] Complete the local, readiness and release checks above.
- [ ] Rerun successful setup with the same configuration. Confirm no duplicate
  resources, users or runners and no weakened environment protections.
- [ ] After all jobs finish, deallocate and restart the runner using
  [runner lifecycle](OPERATIONS.md#runner-lifecycle). Confirm it returns online
  and can complete another dev deployment.
- [ ] Test that promotion rejects PR, skipped-dev, failed, foreign-repository
  and invalid run IDs, plus expired/missing artifacts, before SQL publication.
- [ ] Confirm SQL is Entra-only, public access is disabled, the private endpoint
  is approved and runner DNS resolves inside the configured private subnet.
- [ ] Confirm the VM has no public IP or managed identity, its NSG denies inbound
  access, and deployment identities are not SQL administrators or `db_owner`.
- [ ] In a **disposable** environment, test [cleanup](COST-AND-CLEANUP.md#isolated-cleanup)
  and recreation. Verify its group and runner registration disappear, unrelated
  environments remain intact, and a fresh setup/release works.

Record pass/fail results and failures requiring follow-up. Cleanup is destructive;
do not use your working reference environment or customer data for that test.

## Tested scope and current limits

The [published preview](https://github.com/rayxfelipe/azure-sql-cicd-accelerator/releases/tag/v0.1.0-preview.1)
supports GitHub.com private deployment repositories, Azure public cloud,
Windows/PowerShell 7 setup, and an Ubuntu 24.04 x64 private runner. See the
[supported scope](../README.md#scope-and-honest-status) for prerequisites.

| Evidence | What it establishes |
|---|---|
| November 9, 2026 isolated Windows walkthrough | Setup, dev release, additive PR and exact-artifact production promotion succeeded after a Windows transport fix. |
| Subsequent source/hosted checks | Regression tests, builds and configured publication checks passed. These are not new live Azure release tests. |
| Still pending in maintainer acceptance | Clean successful-setup rerun, VM deallocate/start recovery, live negative-promotion inputs, and cleanup/recreation. The live walkthrough also predates the upgraded deployment Actions. |

The preview is not GA or a production availability/security guarantee. Review
the [security exceptions](../SECURITY.md#infrastructure-preview-exceptions),
shared runner/server isolation and your approval, monitoring and recovery
requirements. Detailed historical evidence is kept in the
[maintainer record](../.github/MAINTAINER-VALIDATION.md), not required for onboarding.
