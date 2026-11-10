# Understand your deployment

After guided setup, you have a private-network foundation for Azure SQL releases
from your own private GitHub repository. After completing the
[quick-start release walkthrough](../README.md#6-deploy-the-initial-schema-to-dev),
you also have a reviewed schema change deployed to dev and promoted to production
using the exact same verified artifact.

Use this guide to understand your resource group, explain the design to others,
or run a short customer demonstration. It describes the template's intended
topology, not a live health report or proof that your deployment succeeded.
Check your own resources and [acceptance evidence](VALIDATION.md).

## What completion means

These are different milestones:

- **Guided setup:** provisions infrastructure, configures GitHub and SQL
  deployment permissions, and verifies both environments' OIDC/private SQL
  readiness before enabling releases.
- **Initial dev release:** builds a DACPAC (the compiled SQL schema package),
  publishes the sample schema to dev, and runs rollback smoke tests.
- **Reviewed change and promotion:** a PR validates without Azure access; merging
  deploys dev; a separate production dispatch validates and reuses that dev
  release's exact artifact without rebuilding.

Setup alone does not publish the sample schema or prove production promotion.
The deployment identities receive explicit SQL grants, not SQL administrator
access or membership in `db_owner`. The initial setup operator needs broader
[setup permissions](SETUP.md#initial-setup-permissions-versus-routine-releases).

## What is in your Azure resource group?

Names below are patterns: `<prefix>` is your configured `resourcePrefix`;
`<suffix>` is the generated SQL server suffix. Region, address ranges and VM
size come from your setup configuration. Never substitute the template
maintainer's or another adopter's resources.

| Purpose | Expected resources / naming patterns | Why they exist |
|---|---|---|
| Database hosting | Logical SQL server `sql-<prefix>-<suffix>` | Hosts both databases and their shared Entra administrator/private-access settings. This is a managed logical server, not another VM. |
| Deployment targets | `sqldb-<prefix>-dev`, `sqldb-<prefix>-prod` | Separate dev and production databases; the starter uses Basic, 5-DTU sizing for each. |
| Passwordless deployment identities | `id-<prefix>-dev`, `id-<prefix>-prod` | Separate user-assigned managed identities with repository/environment-specific GitHub OIDC federation and contained SQL users. Neither identity is attached to the runner VM. |
| Private execution | `vm-<prefix>-runner`, its managed OS disk and `nic-<prefix>-runner` | One persistent Ubuntu runner executes SQL deployment and verification inside the VNet. The VM has no public IP or managed identity; Linux password authentication is disabled. |
| Network separation | `vnet-<prefix>` with `runner` and `private-endpoints` subnets | Separates runner compute from the SQL private endpoint. |
| Runner inbound protection | `nsg-<prefix>-runner` | Attached to the runner subnet, with an explicit deny-all-inbound rule. The supported setup does not require inbound SSH. |
| Outbound connectivity | `nat-<prefix>`, `pip-<prefix>-egress` | Lets the runner initiate outbound connections to GitHub, Azure services and package sources. This public IP is for outbound NAT, not inbound access to the VM or SQL. |
| Private SQL access | `pe-<prefix>-sql` and its generated network interface | Connects the VNet privately to the SQL server, serving both databases. The private endpoint connection should be approved. |
| Private name resolution | `privatelink.database.windows.net`, its VNet link and the endpoint's DNS zone group | Lets the normal SQL server hostname resolve to its private-endpoint address from the runner network. |

Regional resources use your configured Azure region; the private DNS zone and
its link use the `global` location. The infrastructure definitions are in
[main.bicep](../infra/main.bicep), the
[SQL module](../infra/modules/sql.bicep), and the
[private runner module](../infra/modules/private-runner.bicep).

### Why your resource count may differ

Do not use a fixed resource count as a readiness test. Azure Portal and CLI
views may include different child/system resources:

- SQL's `master` is a system database, not a third application environment.
- The VM's OS disk and the private endpoint's network interface have generated
  names. They support existing components, not additional runners.
- Federated credentials, role assignments, DNS records/links and zone groups
  may appear under their parent resources or separate inventory views. The
  identities' Azure Reader assignments are separate from their SQL grants.
- Azure policy or later operator changes may add resources, such as another
  subnet NSG. Inspect their actual associations and rules; do not assume they
  are part of the template or delete them merely because they are additional.

GitHub environments (`dev`, `production`), variables, workflows, runner
registration and build artifacts are **GitHub objects**, not Azure resources.
The public template repository is build-only; this deployed topology belongs
to your own private adopter repository.

## How the components work together

Keep three different connections clear:

1. **Execution:** the private runner initiates an outbound connection to GitHub
   and receives eligible deployment jobs. PR builds run on GitHub-hosted runners,
   not this VM. GitHub does not need an inbound connection to your VNet.
2. **Authentication:** a trusted deployment job obtains a short-lived GitHub OIDC
   token. Entra validates the repository/environment-specific federation for the
   selected identity, allowing Azure sign-in and an Entra token for SQL. The
   identity's contained SQL user and explicit grants authorize the deployment.
   No Azure client secret or SQL password is stored by setup.
3. **SQL connectivity:** the runner resolves the SQL hostname through private
   DNS and connects through the private endpoint. SQL public network access is
   disabled, Entra-only authentication is enabled, and minimum TLS is 1.2.
   NAT enables outbound service access; it does not carry the private SQL path.

OIDC does not provide network connectivity, and a private endpoint does not
grant database permissions. Both paths must work. An ordinary laptop outside
the connected private network cannot reach SQL merely by signing into Azure;
do not enable public access just to make a demonstration work.

## A 10-minute Azure Portal and GitHub walkthrough

Start with this explanation:

> This environment shows a reviewed database change moving from GitHub to dev,
> being tested, and then promoting the exact same release artifact to production,
> without SQL passwords or public database access.

Then show the following in **your own** deployment:

| Stop | Where to look | What to explain or verify |
|---|---|---|
| 1. Overview | Resource group > Resources; group/filter by resource type | Identify database, identity, compute and network components using the table above. This is a database release foundation, not a deployed application frontend/API. |
| 2. Database targets | SQL server > SQL databases | Show dev and prod separately; distinguish `master`. Confirm the configured tier rather than claiming production-grade availability. |
| 3. SQL access controls | SQL server > Networking and Microsoft Entra settings | Show public access disabled, the approved private endpoint and Entra-only authentication. TLS minimum is 1.2. Portal labels can change. |
| 4. Deployment trust | Each managed identity > Federated credentials | Explain separate dev/production trust bound to your GitHub repository and environment. These are deployment identities, not the setup administrator or VM identity. |
| 5. Private execution/network | Runner VM > Networking; VNet > Subnets; runner NSG; private DNS zone | Show no VM public IP, the runner subnet's deny-inbound rule, outbound NAT, and the DNS zone's link to the VNet. Do not describe default outbound access as an egress allowlist. |
| 6. Release evidence | Your private repository > Actions | Show a PR build with dev skipped, a successful main-branch dev deployment/smoke test, and production promotion. Compare the recorded source run, commit and exact artifact ID. |

Before sharing your screen, close local configuration/state/key files and
unredacted setup logs. Show only approved resource details; identifiers are not
passwords but can still reveal tenant, subscription or infrastructure context.
Never display access tokens, private keys or credentials.

### Read-only walkthrough or live release?

- **Read-only:** the runner may remain deallocated. Portal configuration and
  historical workflow results can be discussed without starting it. Historical
  success is dated evidence, not proof of current runner or DNS health.
- **Live:** start the existing runner using the
  [runner lifecycle guidance](OPERATIONS.md#runner-lifecycle), and wait until
  GitHub shows it idle/online before dispatching. Keep it running until every
  deployment and verification job finishes. Do not rerun setup just to start it.
- **Promotion:** artifacts expire after 14 days. If the selected artifact
  expired, produce a new successful main-branch dev release and promote that
  run. Never rebuild a separate production artifact. See
  [production promotion](OPERATIONS.md#production-promotion).

Use your own passing run links and the
[quick-start completion checklist](../README.md#completion-checklist), not the
maintainer's private trial evidence, as proof for your demonstration.

## What this starter does not promise

The two databases share a logical server, private network and persistent runner.
Separate identities/databases are not independent infrastructure or strong
dev/production compute isolation. The Basic tiers and local backup redundancy
are starter choices, not a highly available production design.

The preview does not configure SQL auditing/retention, threat detection alerts,
additional VM host encryption, or a full operational monitoring/recovery
solution. Review the [security policy and exact preview exceptions](../SECURITY.md),
then choose production tiers, isolation, auditing, monitoring, recovery and
governance controls appropriate to the workload. Manual production dispatch is
not two-person approval; configure reviewers and protect the adopter's `main`.
The source repository's protection settings are not copied by template creation.

For ongoing use, follow [releases and operations](OPERATIONS.md), the remaining
[acceptance checks](VALIDATION.md#fresh-repository-acceptance-separate-azure-environment),
and [cost/cleanup guidance](COST-AND-CLEANUP.md). VM deallocation stops compute
billing, not SQL, disk or networking charges. Cleanup is destructive and must
target only the dedicated adopter-owned resource group.
