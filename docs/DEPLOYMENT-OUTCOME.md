# Understand your deployment

Use this guide to identify your Azure resources and explain the design in a
customer walkthrough. It describes the intended topology, not a live health
report. Follow [Validate your deployment](VALIDATION.md) to check your own results.

## What completion means

- **Setup:** infrastructure, GitHub configuration and SQL grants are ready, with
  both environments' OIDC/private SQL checks passed.
- **Initial release:** a DACPAC (compiled SQL schema package) is deployed to dev
  and smoke-tested.
- **Reviewed promotion:** a PR validates without Azure access; merging deploys
  dev; production reuses that verified artifact without rebuilding.

Setup alone does not publish the schema. Complete the
[release walkthrough](../README.md#6-deploy-the-initial-schema-to-dev).

## What is in your Azure resource group?

Names below are patterns: `<prefix>` is your configured `resourcePrefix`;
`<suffix>` is the generated SQL server suffix. Region, address ranges and VM
size come from your setup configuration. Never substitute the template
maintainer's or another adopter's resources.

| Purpose | Expected resources / naming patterns | Why they exist |
|---|---|---|
| Database hosting | Logical SQL server `sql-<prefix>-<suffix>` | Hosts both databases and shared access settings; it is not another VM. |
| Deployment targets | `sqldb-<prefix>-dev`, `sqldb-<prefix>-prod` | Separate dev and production databases; the starter uses Basic, 5-DTU sizing for each. |
| Deployment identities | `id-<prefix>-dev`, `id-<prefix>-prod` | Separate managed identities with repository/environment-specific OIDC trust and SQL users. Neither is attached to the VM. |
| Private execution | `vm-<prefix>-runner`, its OS disk and `nic-<prefix>-runner` | One persistent Ubuntu runner, with no public IP or managed identity and no Linux password authentication. |
| Network separation | `vnet-<prefix>` with `runner` and `private-endpoints` subnets | Separates runner compute from the SQL private endpoint. |
| Runner inbound protection | `nsg-<prefix>-runner` | Attached to the runner subnet, with an explicit deny-all-inbound rule. The supported setup does not require inbound SSH. |
| Outbound connectivity | `nat-<prefix>`, `pip-<prefix>-egress` | Outbound access to GitHub, Azure services and packages; not an inbound VM/SQL endpoint. |
| Private SQL access | `pe-<prefix>-sql` and its generated network interface | Private access to the server for both databases; the connection should be approved. |
| Private DNS | `privatelink.database.windows.net`, its VNet link and endpoint DNS zone group | Resolves the normal SQL hostname to its private-endpoint address inside the runner network. |

Regional resources use your configured Azure region; the private DNS zone and
its link use the `global` location. The infrastructure definitions are in
[main.bicep](../infra/main.bicep), the
[SQL module](../infra/modules/sql.bicep), and the
[private runner module](../infra/modules/private-runner.bicep).

### Why your resource count may differ

Do not use a fixed resource count as a readiness test:

- SQL's `master` is a system database, not a third application environment.
- Disks/NICs have generated names. Child resources such as federation, role
  assignments and DNS records may appear in different inventory views.
- Policy or operator changes may add resources, such as another subnet NSG.
  Inspect their associations/rules; do not delete them just because they are additional.

GitHub environments (`dev`, `production`), variables, workflows, runner
registration and build artifacts are **GitHub objects**, not Azure resources.
The public template repository is build-only; this deployed topology belongs
to your own private adopter repository.

## How the components work together

1. **Execution:** the private runner connects outward to GitHub for deployment
   jobs. PR builds use GitHub-hosted runners. No inbound GitHub connection is needed.
2. **Authentication:** a trusted job uses short-lived GitHub OIDC federation to
   sign into Azure as the environment's identity and obtain an Entra SQL token.
   Explicit SQL grants, not administrator access or `db_owner`, authorize deployment.
   Setup stores no Azure client secret or SQL password. Azure Reader role
   assignments and SQL grants serve different purposes.
3. **Connectivity:** private DNS resolves SQL through the private endpoint.
   Public SQL access is disabled, authentication is Entra-only, and minimum
   TLS is 1.2. NAT serves outbound connections, not this private SQL path.

OIDC is not network access; a private endpoint is not database authorization.
A laptop outside the connected network cannot reach SQL just by signing in.
Do not enable public access for a demonstration. The setup operator's broader
permissions are explained in [guided setup](SETUP.md#initial-setup-permissions-versus-routine-releases).

## A 10-minute Azure Portal and GitHub walkthrough

Start with this explanation:

> This environment shows a reviewed database change moving from GitHub to dev,
> being tested, and then promoting the exact same release artifact to production,
> without SQL passwords or public database access.

Then show the following in **your own** deployment:

| Stop | Where to look | What to explain or verify |
|---|---|---|
| 1. Overview | Resource group > Resources; group by type | Identify the resource layers. This is a release foundation, not an application frontend/API. |
| 2. Targets | SQL server > SQL databases | Show dev/prod, distinguish `master`, and confirm the configured tier. |
| 3. SQL controls | SQL server > Networking and Microsoft Entra settings | Show public access disabled, approved private endpoint, Entra-only authentication and TLS 1.2 minimum. |
| 4. Trust | Managed identities > Federated credentials | Show separate repository/environment trust, not the setup administrator or VM identity. |
| 5. Private network | VM > Networking; VNet/subnets; NSG; private DNS zone | Show no VM public IP, deny-inbound rule, NAT and DNS/VNet link. Outbound NAT is not an egress allowlist. |
| 6. Release evidence | Your private repository > Actions | Show PR/dev/production results and compare source run, commit and exact artifact ID. |

Portal labels can change; focus on the settings, not exact menu wording.

Before sharing your screen, close local configuration/state/key files and
unredacted setup logs. Show only approved resource details; identifiers are not
passwords but can still reveal tenant, subscription or infrastructure context.
Never display access tokens, private keys or credentials.

### Read-only walkthrough or live release?

- **Read-only:** the runner can stay deallocated; no start is needed. Historical
  results are dated evidence, not current runner/DNS health.
- **Live:** start the existing runner using the
  [runner lifecycle guidance](OPERATIONS.md#runner-lifecycle), and wait until
  GitHub shows it idle/online. Keep it running until all jobs finish; no setup
  rerun is needed just to start it.
- **Promotion:** artifacts expire after 14 days. If the selected artifact
  expired, create a new successful main-branch dev release, not a separate
  production build. See
  [production promotion](OPERATIONS.md#production-promotion).

Use your own [validation results](VALIDATION.md), not maintainer trial links.

## What this starter does not promise

Dev/prod share a server, network and persistent runner; identities/databases are
not strong infrastructure isolation. Basic tiers and local backup redundancy
are not a highly available production design.

Review the [security exceptions](../SECURITY.md#infrastructure-preview-exceptions)
and choose appropriate auditing, monitoring, recovery, isolation and database
tiers. Protect your own `main` and configure production reviewers: manual dispatch
is not two-person approval, and source protection settings are not copied.

Next: [Validate your deployment](VALIDATION.md), [operations](OPERATIONS.md) and
[cost/cleanup](COST-AND-CLEANUP.md). Deallocation leaves SQL/disk/network charges;
cleanup is destructive and only for the dedicated adopter-owned group.
