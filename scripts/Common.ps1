Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

function Invoke-CheckedCommand {
    param([string] $Command, [string[]] $Arguments)
    $output = & $Command @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Command failed with exit code $LASTEXITCODE." }
    $output
}

function Invoke-GithubApi {
    param([string] $Path, [string] $Method = 'GET', [object] $Body)
    $arguments = @('api', '--method', $Method, $Path)
    if ($null -ne $Body) {
        $response = $Body | ConvertTo-Json -Depth 15 -Compress | & gh @arguments --input -
        if ($LASTEXITCODE -ne 0) { throw "GitHub API $Method $Path failed." }
    }
    else { $response = Invoke-CheckedCommand gh $arguments }
    if ($response) { ($response -join "`n") | ConvertFrom-Json }
}

function Set-GithubVariable {
    param([string] $Repository, [string] $Name, [string] $Value, [string] $Environment)
    $arguments = @('variable', 'set', $Name, '--repo', $Repository, '--body', $Value)
    if ($Environment) { $arguments += @('--env', $Environment) }
    $null = Invoke-CheckedCommand gh $arguments
}

function Update-SetupState {
    param([string] $Path, [hashtable] $Values)
    $state = if (Test-Path -LiteralPath $Path) {
        Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable
    }
    else { @{} }
    foreach ($entry in $Values.GetEnumerator()) { $state[$entry.Key] = $entry.Value }
    $null = New-Item -ItemType Directory -Path (Split-Path $Path -Parent) -Force
    $state | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $Path
}

function Get-Ipv4Cidr {
    param([string] $Cidr)
    if ($Cidr -notmatch '^(\d{1,3}(?:\.\d{1,3}){3})/(\d{1,2})$') { throw "Invalid IPv4 CIDR: $Cidr" }
    $ip = [System.Net.IPAddress]::Parse($Matches[1])
    $prefix = [int]$Matches[2]
    if ($ip.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork -or $prefix -notin 1..32) {
        throw "Invalid IPv4 CIDR: $Cidr"
    }
    $bytes = $ip.GetAddressBytes()
    [uint64]$address = ([uint64]$bytes[0] -shl 24) -bor ([uint64]$bytes[1] -shl 16) -bor ([uint64]$bytes[2] -shl 8) -bor $bytes[3]
    [uint64]$size = [uint64][Math]::Pow(2, 32 - $prefix)
    [uint64]$start = $address - ($address % $size)
    @{ Start = $start; End = $start + $size - 1; Address = $address; Prefix = $prefix }
}

function Test-AddressInCidr {
    param([string] $Address, [string] $Cidr)
    $network = Get-Ipv4Cidr $Cidr
    $ip = [System.Net.IPAddress]::Parse($Address)
    if ($ip.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) { return $false }
    $value = Get-Ipv4Cidr "$Address/32"
    $value.Start -ge $network.Start -and $value.Start -le $network.End
}

function Assert-PrivateSqlConnection {
    param([string] $ServerFqdn, [string] $PrivateEndpointCidr)
    if ($ServerFqdn -notmatch '^[a-z0-9-]+\.database\.windows\.net$') { throw 'SQL_SERVER_FQDN must be an Azure public-cloud SQL hostname, without a port.' }
    $addresses = [System.Net.Dns]::GetHostAddresses($ServerFqdn)
    if ($addresses.Count -eq 0) { throw 'SQL hostname did not resolve.' }
    foreach ($address in $addresses) {
        if (-not (Test-AddressInCidr $address.ToString() $PrivateEndpointCidr)) {
            throw "SQL resolved outside the configured private-endpoint subnet: $address. Check private DNS and run inside the accelerator VNet."
        }
    }
    Write-Output "SQL private endpoint: $($addresses -join ', ')"
    $client = [System.Net.Sockets.TcpClient]::new()
    try {
        if (-not $client.ConnectAsync($ServerFqdn, 1433).Wait([TimeSpan]::FromSeconds(30))) { throw 'Private SQL TCP connection timed out.' }
        if (-not $client.Connected) { throw 'Private SQL TCP connection failed.' }
    }
    finally { $client.Dispose() }
}

function Assert-SetupVerificationJobs {
    param([object[]] $Jobs)
    foreach ($name in @('OIDC (dev)', 'OIDC (production)', 'SQL (dev)', 'SQL (production)')) {
        $matching = @($Jobs | Where-Object name -eq $name)
        if ($matching.Count -ne 1 -or $matching[0].conclusion -ne 'success') {
            throw "Setup verification job '$name' did not succeed. A skipped job is not readiness evidence."
        }
    }
}

function Assert-NoActiveReleaseRuns {
    param([string] $Repository)
    foreach ($status in @('in_progress', 'queued', 'waiting', 'pending', 'requested')) {
        $runs = Invoke-GithubApi "repos/$Repository/actions/runs?status=$status&per_page=100"
        if ($runs.total_count -gt 100) { throw 'Cannot verify quiescent releases from a truncated workflow list.' }
        $active = @($runs.workflow_runs | Where-Object {
            $_.head_branch -eq 'main' -and $_.path -in @('.github/workflows/database-ci.yml', '.github/workflows/promote-production.yml')
        })
        if ($active.Count -gt 0) {
            throw "Wait for or cancel active main-branch CI/promotion before changing infrastructure: $($active[0].html_url)"
        }
    }
}

function Read-SetupConfiguration {
    param([string] $Path)
    $config = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    foreach ($field in @('subscriptionId', 'repository', 'location', 'resourceGroupName', 'resourcePrefix',
        'administratorObjectId', 'administratorLogin', 'administratorPrincipalType', 'runnerVmSize', 'runnerAdminUsername',
        'vnetAddressPrefix', 'runnerSubnetPrefix', 'privateEndpointSubnetPrefix')) {
        if (-not $config.PSObject.Properties[$field] -or [string]::IsNullOrWhiteSpace([string]$config.$field)) {
            throw "Configuration field '$field' is required."
        }
    }
    foreach ($field in @('subscriptionId', 'administratorObjectId')) {
        $guid = [guid]::Empty
        if (-not [guid]::TryParse($config.$field, [ref]$guid) -or $guid -eq [guid]::Empty) {
            throw "'$field' must be a nonzero GUID. Replace example placeholders."
        }
    }
    if ($config.repository -notmatch '^[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9_.-]+$' -or $config.repository -match 'YOUR-') {
        throw 'repository must identify your adopter repository as owner/name.'
    }
    if ($config.resourcePrefix -notmatch '^[a-z][a-z0-9]{2,15}$') { throw 'resourcePrefix must be 3-16 lowercase alphanumeric characters, starting with a letter.' }
    if ($config.resourceGroupName -notmatch '^[A-Za-z0-9_-]{1,90}$') { throw 'resourceGroupName must be 1-90 letters, digits, underscores or hyphens.' }
    if ($config.location -notmatch '^[a-z0-9]+$') { throw 'location must be an Azure region identifier.' }
    if ($config.administratorPrincipalType -notin @('User', 'Group')) { throw 'administratorPrincipalType must be User or Group.' }
    if ($config.administratorLogin -match 'YOUR-' -or $config.administratorLogin.Length -gt 128) { throw 'Set a valid administratorLogin, at most 128 characters.' }
    if ($config.runnerVmSize -notmatch '^Standard_[A-Za-z0-9_]+$') { throw 'runnerVmSize must be an Azure Standard VM size.' }
    if ($config.runnerAdminUsername -notmatch '^[a-z][a-z0-9_-]{0,31}$' -or $config.runnerAdminUsername -in @('root', 'admin', 'administrator', 'user', 'test', 'ubuntu', 'guest')) {
        throw 'runnerAdminUsername must be a non-reserved Linux username of at most 32 lowercase letters, digits, underscores or hyphens.'
    }
    $vnet = Get-Ipv4Cidr $config.vnetAddressPrefix
    $runner = Get-Ipv4Cidr $config.runnerSubnetPrefix
    $endpoint = Get-Ipv4Cidr $config.privateEndpointSubnetPrefix
    foreach ($network in @($vnet, $runner, $endpoint)) {
        if ($network.Address -ne $network.Start -or $network.Prefix -notin 8..28) { throw 'CIDRs must be network-aligned and have prefix lengths from 8 through 28.' }
        $private = $false
        foreach ($range in @('10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16')) {
            $bounds = Get-Ipv4Cidr $range
            if ($network.Start -ge $bounds.Start -and $network.End -le $bounds.End) { $private = $true }
        }
        if (-not $private) { throw 'Only RFC1918 private IPv4 network ranges are supported.' }
    }
    foreach ($subnet in @($runner, $endpoint)) {
        if ($subnet.Start -lt $vnet.Start -or $subnet.End -gt $vnet.End) { throw 'Both subnets must be inside the VNet.' }
    }
    if ($runner.Start -le $endpoint.End -and $endpoint.Start -le $runner.End) { throw 'Runner and private endpoint subnets must not overlap.' }
    $config
}

function Assert-OwnedResourceGroup {
    param([object] $Group, [string] $Repository)
    if (-not $Group.tags -or -not $Group.tags.PSObject.Properties['managed-by'] -or
        -not $Group.tags.PSObject.Properties['repository'] -or
        $Group.tags.'managed-by' -ne 'azure-sql-cicd-accelerator' -or $Group.tags.repository -ne $Repository) {
        throw 'Refusing to use an existing resource group not owned by this accelerator repository. Choose a NEW isolated resourceGroupName.'
    }
}

function Assert-TrustedRelease {
    param([object] $Run, [object[]] $Jobs, [object[]] $Artifacts, [string] $Repository)
    if ($Run.status -ne 'completed' -or $Run.conclusion -ne 'success' -or $Run.head_branch -ne 'main' -or
        $Run.path -ne '.github/workflows/database-ci.yml' -or $Run.event -notin @('push', 'workflow_dispatch') -or
        $Run.head_repository.full_name -ne $Repository) {
        throw 'Only a successful trusted main-branch build AND dev deployment can be promoted.'
    }
    $deployJobs = @($Jobs | Where-Object name -eq 'deploy-dev')
    if ($deployJobs.Count -ne 1 -or $deployJobs[0].conclusion -ne 'success') { throw 'Source run did not successfully deploy dev (a skipped job is not a release).' }
    $releaseArtifacts = @($Artifacts | Where-Object name -eq 'database-release')
    if ($releaseArtifacts.Count -ne 1 -or $releaseArtifacts[0].expired) { throw 'Source must contain exactly one unexpired database-release artifact.' }
    $releaseArtifacts[0]
}

function Remove-AcceleratorResources {
    param([object] $Configuration, [string] $StatePath, [bool] $ResourceGroupExists)
    $repo = Invoke-GithubApi "repos/$($Configuration.repository)"
    $runnerName = "sql-$($repo.id)-$($Configuration.resourcePrefix)"
    $runners = Invoke-GithubApi "repos/$($Configuration.repository)/actions/runners?per_page=100"
    if ($runners.total_count -gt 100) { throw 'Refusing cleanup with a truncated runner list.' }
    if ($ResourceGroupExists) {
        $targets = @($runners.runners | Where-Object name -eq $runnerName)
        $cleanup = @{
            configuration = $Configuration
            repositoryId = $repo.id
            runnerIds = @($targets | ForEach-Object id)
        }
    }
    else {
        $state = if (Test-Path -LiteralPath $StatePath) {
            Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json -AsHashtable
        }
        else { @{} }
        if (-not $state['cleanup']) {
            if (@($runners.runners | Where-Object name -eq $runnerName).Count -gt 0) {
                throw 'Azure group is absent but a matching runner remains. No saved cleanup record proves its ownership; inspect the registration manually rather than deleting by name.'
            }
            Write-Host 'Resource group is already absent and no matching runner remains. GitHub settings are unchanged.'
            return
        }
        $cleanup = $state['cleanup']
        foreach ($field in @('subscriptionId', 'repository', 'resourceGroupName', 'resourcePrefix')) {
            if ($cleanup.configuration[$field] -ne $Configuration.$field) { throw "Saved cleanup '$field' differs. Refusing to remove runner registrations for another deployment." }
        }
        if ($cleanup.repositoryId -ne $repo.id) { throw 'Saved cleanup repository ID differs. Refusing to use registrations from another repository.' }
        $targets = @($runners.runners | Where-Object { $_.id -in $cleanup.runnerIds })
    }
    foreach ($runner in $targets) {
        if ($runner.busy) { throw 'Accelerator runner is busy. Wait for or cancel its workflow before cleanup.' }
    }
    Set-GithubVariable $Configuration.repository 'SETUP_COMPLETE' 'false'
    Set-GithubVariable $Configuration.repository 'SETUP_IN_PROGRESS' 'false'
    Assert-NoActiveReleaseRuns $Configuration.repository
    if ($ResourceGroupExists) {
        Update-SetupState $StatePath @{ configuration = $Configuration; complete = $false; cleanup = $cleanup }
        $null = Invoke-CheckedCommand az @('group', 'delete', '--subscription', $Configuration.subscriptionId, '--name', $Configuration.resourceGroupName, '--yes')
        $remaining = (Invoke-CheckedCommand az @('group', 'exists', '--subscription', $Configuration.subscriptionId, '--name', $Configuration.resourceGroupName)) -join ''
        if ($remaining -ne 'false') { throw 'Resource group deletion has not completed. Runner registrations were retained; rerun cleanup once Azure deletion completes.' }
    }
    foreach ($runner in $targets) {
        $null = Invoke-GithubApi "repos/$($Configuration.repository)/actions/runners/$($runner.id)" DELETE
    }
    Update-SetupState $StatePath @{ complete = $false; cleanup = $null }
    Write-Host 'Accelerator Azure resources deleted; recorded runner registrations removed and GitHub deployments disabled. Repository, environments and OIDC subject customization were retained.'
}

function Invoke-PrivateRunCommand {
    param([object] $Configuration, [string] $Script, [string[]] $ProtectedParameters, [int] $TimeoutSeconds = 600)
    $name = "accelerator-$([guid]::NewGuid().ToString('N'))"
    $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Script.Replace("`r`n", "`n")))
    $arguments = @('--subscription', $Configuration.subscriptionId, '--resource-group', $Configuration.resourceGroup,
        '--vm-name', $Configuration.runnerVm, '--run-command-name', $name)
    $primaryError = $null
    try {
        $null = Invoke-CheckedCommand az (@('vm', 'run-command', 'create') + $arguments + @('--location', $Configuration.location,
            '--script', "printf '%s' '$encoded' | base64 --decode | bash", '--protected-parameters') +
            $ProtectedParameters + @('--timeout-in-seconds', "$TimeoutSeconds", '--output', 'none'))
        $result = (Invoke-CheckedCommand az (@('vm', 'run-command', 'show') + $arguments +
            @('--expand', 'instanceView', '--query', 'instanceView', '--output', 'json'))) -join "`n" | ConvertFrom-Json
        if ($result.executionState -ne 'Succeeded' -or $result.exitCode -ne 0) {
            throw "Private Run Command failed: $($result | ConvertTo-Json -Depth 5 -Compress)"
        }
        $result.output
    }
    catch { $primaryError = $_ }
    finally {
        try {
            $null = Invoke-CheckedCommand az (@('vm', 'run-command', 'delete') + $arguments + @('--yes', '--output', 'none'))
        }
        catch {
            $cleanupError = $_
            if ($null -ne $primaryError) {
                throw [AggregateException]::new(
                    "Private Run Command '$name' failed: $($primaryError.Exception.Message). Cleanup also failed: $($cleanupError.Exception.Message). Remove the named command after correcting the cleanup failure.",
                    [Exception[]]@($primaryError.Exception, $cleanupError.Exception))
            }
            throw [InvalidOperationException]::new(
                "Private Run Command '$name' executed successfully but cleanup failed: $($cleanupError.Exception.Message). Remove the named command after correcting the cleanup failure.",
                $cleanupError.Exception)
        }
    }
    if ($null -ne $primaryError) { throw $primaryError }
}

function Invoke-WorkflowAndWait {
    param([string] $Repository, [string] $Workflow, [int] $TimeoutMinutes = 30)
    $requestId = [guid]::NewGuid().ToString('N')
    $null = Invoke-GithubApi "repos/$Repository/actions/workflows/$Workflow/dispatches" POST @{
        ref = 'main'; inputs = @{ request_id = $requestId }
    }
    $deadline = [DateTime]::UtcNow.AddMinutes($TimeoutMinutes)
    $runId = $null
    $previousStatus = ''
    while ([DateTime]::UtcNow -lt $deadline) {
        if (-not $runId) {
            $runs = Invoke-GithubApi "repos/$Repository/actions/workflows/$Workflow/runs?event=workflow_dispatch&branch=main&per_page=20"
            $matching = @($runs.workflow_runs | Where-Object display_title -eq "Setup verification $requestId")
            if ($matching.Count -gt 1) { throw 'Ambiguous setup verification run.' }
            if ($matching.Count -eq 1) { $runId = $matching[0].id }
        }
        if ($runId) {
            $run = Invoke-GithubApi "repos/$Repository/actions/runs/$runId"
            if ($run.status -ne $previousStatus) { Write-Host "Verification: $($run.status) - $($run.html_url)"; $previousStatus = $run.status }
            if ($run.status -eq 'completed') {
                if ($run.conclusion -ne 'success') { throw "Readiness verification failed ($($run.conclusion)). Inspect $($run.html_url); deployments remain disabled." }
                $jobs = Invoke-GithubApi "repos/$Repository/actions/runs/$runId/jobs?filter=latest&per_page=100"
                Assert-SetupVerificationJobs $jobs.jobs
                return $run
            }
        }
        Start-Sleep -Seconds 10
    }
    throw "Verification timed out after $TimeoutMinutes minutes. Check runner state, environment approvals and GitHub Actions. Deployments remain disabled; rerun setup after resolving the blocker."
}
