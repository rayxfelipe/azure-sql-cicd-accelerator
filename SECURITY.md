# Security policy

## Supported scope

The accelerator is a preview starter for isolated Azure SQL CI/CD environments,
not a production security certification. The supported runtime and deployment
limits are listed in the [README](README.md#scope-and-honest-status).
Use the latest published preview; older snapshots are not independently serviced.

The distribution template must remain build-only: no registered self-hosted
runner, deployment credentials or Azure federation for the template repository.
Create a separate private deployment repository with its own setup and OIDC trust.
Never enable deployment gates manually to bypass readiness.

## Reporting a concern

Use **Security > Report a vulnerability** to report privately to the distribution
repository; private vulnerability reporting is enabled there. Adopter copies
must configure their own reporting channel. If private reporting is unavailable
in a copy, request a private channel without including sensitive details in an issue.
Do not post credentials, access tokens, private keys, customer data or unredacted
setup state/logs in public issues, pull requests or discussions.

Include affected revision, reproduction steps and impact through the private
channel. Do not test against another adopter's resources. No response-time SLA,
managed operations or security support contract is provided.

## Verification boundaries

Local secret/history scans, workflow validation and infrastructure policy checks
reduce risk but do not prove the absence of vulnerabilities. See the
[validation record](docs/VALIDATION.md) for dated evidence and remaining gates.
Production approvals, stronger runner isolation, monitoring, recovery and
appropriate database tiers remain adopter responsibilities.

Actions are pinned to immutable commits and checked weekly by Dependabot.
Review updates rather than automatically merging them. The SQL build SDK,
SqlPackage, PowerShell SqlServer module and runner distribution are separately
pinned; review their vendor advisories and supported versions when updating.
NuGet package auditing alone does not cover every library bundled inside these
tools.

The public distribution repository requires pull requests and successful
`build`/`security` checks on an up-to-date branch, including for administrators.
Force pushes and branch deletion are disabled. The sole-maintainer policy uses
zero mandatory approvals; it does not provide two-person review. External
contributors' workflow runs require maintainer approval. GitHub secret scanning
and push protection are enabled in addition to the local Gitleaks workflow;
neither guarantees that every secret or identifier will be detected.

## Infrastructure preview exceptions

The raw Checkov 3.4.3 ARM scan on November 9, 2026 reported **16 passed and
10 failed checks**, with 18 resource expressions and no parsing errors.
These are real policy limitations of the starter, not a clean security scan.
The [baseline](.checkov.baseline) accepts only the listed checks on the exact
compiled runner, SQL server and database resource expressions. CI displays these
as skipped and rejects new, non-baselined findings. Do not regenerate the baseline
automatically or add blanket check-ID exclusions to make a build pass.

| Checks | Resource / preview disposition |
|---|---|
| `CKV_AZURE_23` (two findings), `CKV_AZURE_24` | SQL server/database auditing and retention are not configured. Adopters must choose a logging destination, access controls, retention and budget before using sensitive data. |
| `CKV_AZURE_229` | The Basic database tier is not zone redundant. A production availability target requires a suitable tier and a separately tested design. |
| `CKV_AZURE_25`, `CKV_AZURE_26`, `CKV_AZURE_27` | SQL threat detection and notification recipients are not configured. Assess Defender costs and configure an owned monitoring/alerting process; this preview does not supply one. |
| `CKV_AZURE_50` | VM extension operations remain enabled for the managed Run Command onboarding path. Disabling them breaks the supported setup; repository write access and Azure Run Command permissions must stay restricted. |
| `CKV_AZURE_97`, `CKV_AZURE_151` | Additional VM host encryption is not enabled. Both ARM rules inspect the same setting even though their names mention VMSS/Windows; the runner is a single Linux VM. Validate SKU/feature support and enable it for workloads whose policy requires it. Azure managed-disk encryption at rest is not equivalent to this control. |

These exceptions avoid silently adding paid services, alert destinations or
unsupported VM features to customer setup. They are acceptable only for this
isolated, synthetic-data preview; an adopter's security policy takes precedence.
Changes to resource expressions, scanner versions or this baseline require review.
The baseline is an explicit risk boundary, not a waiver for customer production.
