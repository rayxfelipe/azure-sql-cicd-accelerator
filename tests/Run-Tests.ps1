. (Join-Path (Split-Path $PSScriptRoot) 'scripts/Common.ps1')
$script:passed = 0
function Assert-Test {
    param([bool] $Condition, [string] $Name)
    if (-not $Condition) { throw "FAIL: $Name" }
    $script:passed++
    Write-Host "PASS: $Name"
}
function Assert-Throws {
    param([scriptblock] $Action, [string] $MessagePattern, [string] $Name)
    $caught = $false
    try { & $Action }
    catch {
        if ($_.Exception.Message -notmatch $MessagePattern) { throw }
        $caught = $true
    }
    Assert-Test $caught $Name
}

Assert-Test (Test-AddressInCidr '10.42.2.4' '10.42.2.0/24') 'Configured private subnet is accepted (not a demo-specific range)'
Assert-Test (-not (Test-AddressInCidr '10.42.3.4' '10.42.2.0/24')) 'Wrong private subnet is rejected'
Assert-Test (-not (Test-AddressInCidr '20.42.2.4' '10.42.2.0/24')) 'Public SQL address is rejected'
Assert-Test (-not (Test-AddressInCidr '::1' '10.42.2.0/24')) 'IPv6 does not bypass the IPv4 private-endpoint check'
Assert-Test (Test-AddressInCidr '10.42.2.0' '10.42.2.0/24') 'CIDR first address is included'
Assert-Test (Test-AddressInCidr '10.42.2.255' '10.42.2.0/24') 'CIDR last address is included'
Assert-Throws { Get-Ipv4Cidr '10.42.2.0/33' } 'Invalid IPv4 CIDR' 'Invalid prefix is rejected'
Assert-Throws { Get-Ipv4Cidr 'not-a-network' } 'Invalid IPv4 CIDR' 'Malformed CIDR is rejected'

$owned = [pscustomobject]@{ tags = [pscustomobject]@{ 'managed-by' = 'azure-sql-cicd-accelerator'; repository = 'owner/adopter' } }
Assert-OwnedResourceGroup $owned 'owner/adopter'
Assert-Test $true 'Matching accelerator-owned resource group can be reused'
Assert-Throws { Assert-OwnedResourceGroup $owned 'owner/another' } 'Refusing' 'Different repository resource group is protected'
Assert-Throws { Assert-OwnedResourceGroup ([pscustomobject]@{ tags = $null }) 'owner/adopter' } 'Refusing' 'Untagged baseline resource group is protected'
Assert-Throws { Assert-OwnedResourceGroup ([pscustomobject]@{ tags = [pscustomobject]@{ project = 'demo' } }) 'owner/adopter' } 'Refusing' 'Baseline-style resource group is protected'

$config = @{
    subscriptionId = '11111111-1111-1111-1111-111111111111'; repository = 'owner/adopter'
    location = 'eastus'; resourceGroupName = 'rg-adopter'; resourcePrefix = 'adopter'
    administratorObjectId = '22222222-2222-2222-2222-222222222222'; administratorLogin = 'Setup Admin'
    administratorPrincipalType = 'Group'; runnerVmSize = 'Standard_B2s_v2'; runnerAdminUsername = 'runneradmin'
    vnetAddressPrefix = '172.20.0.0/16'; runnerSubnetPrefix = '172.20.1.0/24'; privateEndpointSubnetPrefix = '172.20.2.0/24'
}
$temporaryFile = Join-Path ([IO.Path]::GetTempPath()) "sql-accelerator-test-$([guid]::NewGuid().ToString('N')).json"
function Write-TestConfiguration {
    param([hashtable] $Value)
    $Value | ConvertTo-Json | Set-Content -LiteralPath $temporaryFile
}
try {
    Write-TestConfiguration $config
    $actual = Read-SetupConfiguration $temporaryFile
    Assert-Test ($actual.resourcePrefix -eq 'adopter' -and $actual.location -eq 'eastus') 'Fresh adopter configuration works outside baseline region and names'
    foreach ($case in @(
        @{ Field = 'subscriptionId'; Value = '00000000-0000-0000-0000-000000000000'; Pattern = 'nonzero GUID'; Name = 'Placeholder subscription is rejected' },
        @{ Field = 'repository'; Value = 'YOUR-OWNER/YOUR-PRIVATE-REPOSITORY'; Pattern = 'owner/name'; Name = 'Placeholder repository is rejected' },
        @{ Field = 'resourcePrefix'; Value = 'Bad Prefix'; Pattern = 'resourcePrefix'; Name = 'Invalid resource name is rejected' },
        @{ Field = 'runnerSubnetPrefix'; Value = '172.21.1.0/24'; Pattern = 'inside'; Name = 'Subnet outside VNet is rejected' },
        @{ Field = 'runnerSubnetPrefix'; Value = '172.20.2.0/25'; Pattern = 'overlap'; Name = 'Overlapping subnets are rejected' },
        @{ Field = 'runnerSubnetPrefix'; Value = '172.20.1.5/24'; Pattern = 'network-aligned'; Name = 'Non-aligned subnet is rejected' },
        @{ Field = 'vnetAddressPrefix'; Value = '20.20.0.0/16'; Pattern = 'RFC1918'; Name = 'Public VNet range is rejected' }
    )) {
        $changed = $config.Clone()
        $changed[$case.Field] = $case.Value
        Write-TestConfiguration $changed
        Assert-Throws { Read-SetupConfiguration $temporaryFile } $case.Pattern $case.Name
    }
}
finally { Remove-Item -LiteralPath $temporaryFile }

$run = [pscustomobject]@{
    status = 'completed'; conclusion = 'success'; head_branch = 'main'; path = '.github/workflows/database-ci.yml'
    event = 'push'; head_repository = [pscustomobject]@{ full_name = 'owner/adopter' }
}
$jobs = @([pscustomobject]@{ name = 'build'; conclusion = 'success' }, [pscustomobject]@{ name = 'deploy-dev'; conclusion = 'success' })
$artifacts = @([pscustomobject]@{ id = 123; name = 'database-release'; expired = $false })
$artifact = Assert-TrustedRelease $run $jobs $artifacts 'owner/adopter'
Assert-Test ($artifact.id -eq 123) 'Successful trusted dev release returns the exact artifact ID'
foreach ($case in @(
    @{ Field = 'event'; Value = 'pull_request'; Name = 'PR run cannot be promoted' },
    @{ Field = 'head_branch'; Value = 'feature'; Name = 'Non-main run cannot be promoted' },
    @{ Field = 'conclusion'; Value = 'failure'; Name = 'Failed run cannot be promoted' },
    @{ Field = 'status'; Value = 'in_progress'; Name = 'Incomplete run cannot be promoted' },
    @{ Field = 'path'; Value = '.github/workflows/other.yml'; Name = 'Different workflow cannot be promoted' }
)) {
    $changed = $run | ConvertTo-Json | ConvertFrom-Json
    $changed.($case.Field) = $case.Value
    Assert-Throws { Assert-TrustedRelease $changed $jobs $artifacts 'owner/adopter' } 'Only a successful trusted' $case.Name
}
Assert-Throws { Assert-TrustedRelease $run $jobs $artifacts 'owner/another' } 'Only a successful trusted' 'Foreign repository cannot be promoted'
foreach ($conclusion in @('skipped', 'failure', 'cancelled')) {
    $badJobs = @([pscustomobject]@{ name = 'deploy-dev'; conclusion = $conclusion })
    Assert-Throws { Assert-TrustedRelease $run $badJobs $artifacts 'owner/adopter' } 'did not successfully deploy dev' "Dev $conclusion is not promotion evidence"
}
Assert-Throws { Assert-TrustedRelease $run @() $artifacts 'owner/adopter' } 'did not successfully deploy dev' 'Missing dev job is rejected'
Assert-Throws { Assert-TrustedRelease $run $jobs @([pscustomobject]@{ name = 'database-release'; expired = $true }) 'owner/adopter' } 'unexpired' 'Expired artifact is rejected'
Assert-Throws { Assert-TrustedRelease $run $jobs @() 'owner/adopter' } 'exactly one' 'Missing artifact is rejected'
Assert-Throws { Assert-TrustedRelease $run $jobs ($artifacts + $artifacts) 'owner/adopter' } 'exactly one' 'Ambiguous artifact is rejected'

$verificationJobs = @('OIDC (dev)', 'OIDC (production)', 'SQL (dev)', 'SQL (production)') |
    ForEach-Object { [pscustomobject]@{ name = $_; conclusion = 'success' } }
Assert-SetupVerificationJobs $verificationJobs
Assert-Test $true 'Both OIDC subjects and private SQL environments must pass readiness'
$verificationJobs[3].conclusion = 'skipped'
Assert-Throws { Assert-SetupVerificationJobs $verificationJobs } 'did not succeed' 'Skipped production readiness cannot enable deployments'
Assert-Throws { Assert-SetupVerificationJobs @() } 'did not succeed' 'Entirely skipped workflow cannot enable deployments'

$originalApi = ${function:Invoke-GithubApi}
$script:activeRuns = @()
function Invoke-GithubApi {
    param([string] $Path, [string] $Method = 'GET', [object] $Body)
    [pscustomobject]@{ total_count = $script:activeRuns.Count; workflow_runs = $script:activeRuns }
}
try {
    Assert-NoActiveReleaseRuns 'owner/adopter'
    Assert-Test $true 'Idle releases allow setup and cleanup'
    $script:activeRuns = @([pscustomobject]@{
        head_branch = 'main'; path = '.github/workflows/promote-production.yml'; html_url = 'https://github.com/owner/adopter/actions/runs/123'
    })
    Assert-Throws { Assert-NoActiveReleaseRuns 'owner/adopter' } 'active main-branch' 'Active production promotion blocks infrastructure changes'
    $script:activeRuns[0].path = '.github/workflows/database-ci.yml'
    Assert-Throws { Assert-NoActiveReleaseRuns 'owner/adopter' } 'active main-branch' 'Active dev CI blocks infrastructure changes'
    $script:activeRuns[0].head_branch = 'feature'
    Assert-NoActiveReleaseRuns 'owner/adopter'
    Assert-Test $true 'Credential-free feature PR build does not block infrastructure changes'
}
finally { Set-Item -Path function:Invoke-GithubApi -Value $originalApi }

$stateFile = Join-Path ([IO.Path]::GetTempPath()) "sql-accelerator-state-test-$([guid]::NewGuid().ToString('N')).json"
try {
    Update-SetupState $stateFile @{
        configuration = $config; complete = $true
        deployment = @{ subscriptionId = $config.subscriptionId; resourceGroup = 'rg-adopter'; runnerVm = 'vm-adopter' }
        repositoryId = 99; runnerName = 'sql-99-adopter'; verificationUrl = 'https://github.com/owner/adopter/actions/runs/123'
    }
    Update-SetupState $stateFile @{ configuration = $config; complete = $false }
    $state = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json
    Assert-Test (-not $state.complete) 'Rerun state is explicitly marked incomplete'
    Assert-Test ($state.deployment.runnerVm -eq 'vm-adopter' -and $state.deployment.resourceGroup -eq 'rg-adopter') 'Early rerun failure retains previous deployment outputs'
    Assert-Test ($state.repositoryId -eq 99 -and $state.runnerName -eq 'sql-99-adopter') 'Early rerun failure retains runner ownership metadata'
    Assert-Test ($state.verificationUrl -eq 'https://github.com/owner/adopter/actions/runs/123') 'Previous verification evidence is retained without claiming current readiness'
    Update-SetupState $stateFile @{ complete = $true; verificationUrl = 'https://github.com/owner/adopter/actions/runs/456' }
    $state = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json
    Assert-Test ($state.complete -and $state.verificationUrl.EndsWith('/456') -and $state.deployment.runnerVm -eq 'vm-adopter') 'Successful state update replaces only supplied fields'
    '{invalid-json' | Set-Content -LiteralPath $stateFile
    Assert-Throws { Update-SetupState $stateFile @{ complete = $false } } 'JSON' 'Invalid existing state fails explicitly rather than being overwritten'
    Assert-Test ((Get-Content -LiteralPath $stateFile -Raw).Trim() -eq '{invalid-json') 'Failed state parse leaves the original file intact'
}
finally { Remove-Item -LiteralPath $stateFile }

function Get-TestError {
    param([scriptblock] $Action)
    try { $null = & $Action }
    catch { return $_ }
    throw 'Expected an error, but the operation succeeded.'
}

$originalNative = ${function:Invoke-CheckedCommand}
$script:nativeCalls = @()
$script:initializationFailure = $true
$script:commandCleanupFailure = $false
$script:guestResult = @{ executionState = 'Succeeded'; exitCode = 0; output = 'Initialized' }
function Invoke-CheckedCommand {
    param([string] $Command, [string[]] $Arguments)
    $script:nativeCalls += ,$Arguments
    if ($Arguments[2] -eq 'create' -and $script:initializationFailure) {
        throw [System.Management.Automation.ErrorRecord]::new(
            [InvalidOperationException]::new('Simulated initialization failure'), 'InitializationFailure',
            [System.Management.Automation.ErrorCategory]::OperationStopped, $null)
    }
    if ($Arguments[2] -eq 'show') { $script:guestResult | ConvertTo-Json -Compress }
    if ($Arguments[2] -eq 'delete' -and $script:commandCleanupFailure) { throw 'Simulated Run Command cleanup failure' }
}
try {
    $configuration = [pscustomobject]@{ subscriptionId = 'test'; resourceGroup = 'rg-adopter'; runnerVm = 'vm-adopter'; location = 'eastus' }
    $errorRecord = Get-TestError { Invoke-PrivateRunCommand $configuration 'exit 1' @('Token=fake-test-value') }
    Assert-Test ($errorRecord.Exception.Message -eq 'Simulated initialization failure') 'Run Command failure is surfaced'
    Assert-Test ($errorRecord.FullyQualifiedErrorId -match 'InitializationFailure') 'Primary error identity is retained when cleanup succeeds'
    Assert-Test ($script:nativeCalls.Count -eq 2 -and $script:nativeCalls[1][2] -eq 'delete') 'Protected Run Command is cleaned up even when initialization fails'
    Assert-Test ($script:nativeCalls[0] -contains '--protected-parameters') 'Bootstrap values use protected Run Command parameters'
    $script:commandCleanupFailure = $true
    $errorRecord = Get-TestError { Invoke-PrivateRunCommand $configuration 'exit 1' @('Token=fake-test-value') }
    Assert-Test ($errorRecord.Exception -is [AggregateException] -and $errorRecord.Exception.InnerExceptions.Count -eq 2) 'Execution and cleanup failures are both retained'
    Assert-Test ($errorRecord.Exception.InnerExceptions[0].Message -eq 'Simulated initialization failure' -and
        $errorRecord.Exception.InnerExceptions[1].Message -eq 'Simulated Run Command cleanup failure') 'Aggregate preserves the primary and secondary failure details'
    Assert-Test ($errorRecord.Exception.Message -match "accelerator-[a-f0-9]{32}" -and $errorRecord.Exception.Message -match 'Cleanup also failed') 'Combined error identifies the Run Command requiring cleanup'
    $script:initializationFailure = $false
    $errorRecord = Get-TestError { Invoke-PrivateRunCommand $configuration 'exit 0' @('Token=fake-test-value') }
    Assert-Test ($errorRecord.Exception.Message -match 'executed successfully but cleanup failed') 'Cleanup-only failure is explicit and does not report overall success'
    $script:guestResult = @{ executionState = 'Failed'; exitCode = 1; output = 'Simulated guest failure' }
    $errorRecord = Get-TestError { Invoke-PrivateRunCommand $configuration 'exit 1' @('Token=fake-test-value') }
    Assert-Test ($errorRecord.Exception -is [AggregateException] -and $errorRecord.Exception.InnerExceptions[0].Message -match 'Simulated guest failure') 'Guest execution failure is retained when cleanup also fails'
    $script:commandCleanupFailure = $false
    Assert-Throws { Invoke-PrivateRunCommand $configuration 'exit 1' @('Token=fake-test-value') } 'Simulated guest failure' 'Guest execution failure is surfaced after successful cleanup'
    $script:guestResult = @{ executionState = 'Succeeded'; exitCode = 0; output = 'Initialized' }
    $script:nativeCalls = @()
    $output = @(Invoke-PrivateRunCommand $configuration 'exit 0' @('Token=fake-test-value'))
    Assert-Test ($output -contains 'Initialized' -and $script:nativeCalls.Count -eq 3) 'Successful execution still returns output and cleans up'
}
finally { Set-Item -Path function:Invoke-CheckedCommand -Value $originalNative }

$originalApi = ${function:Invoke-GithubApi}
$originalVariable = ${function:Set-GithubVariable}
$originalActiveGuard = ${function:Assert-NoActiveReleaseRuns}
$cleanupStateFile = Join-Path ([IO.Path]::GetTempPath()) "sql-accelerator-cleanup-test-$([guid]::NewGuid().ToString('N')).json"
function Reset-CleanupTest {
    $script:cleanupCalls = @()
    $script:azureGroupExists = $true
    $script:azureDeletionFailure = $false
    $script:azureDeletionPending = $false
    $script:runnerDeletionFailure = $false
    $script:activeReleaseFailure = $false
    $script:runnerRecords = @(
        [pscustomobject]@{ id = 7; name = 'sql-99-adopter'; busy = $false },
        [pscustomobject]@{ id = 8; name = 'unrelated-runner'; busy = $false }
    )
    if (Test-Path -LiteralPath $cleanupStateFile) { Remove-Item -LiteralPath $cleanupStateFile }
    Update-SetupState $cleanupStateFile @{ configuration = $config; complete = $true; deployment = @{ runnerVm = 'vm-adopter' } }
}
function Invoke-CheckedCommand {
    param([string] $Command, [string[]] $Arguments)
    if ($Arguments[0] -eq 'group' -and $Arguments[1] -eq 'delete') {
        $script:cleanupCalls += 'delete-azure'
        if ($script:azureDeletionFailure) { throw 'Simulated Azure deletion blocked by lock' }
        if (-not $script:azureDeletionPending) { $script:azureGroupExists = $false }
    }
    elseif ($Arguments[0] -eq 'group' -and $Arguments[1] -eq 'exists') { $script:azureGroupExists.ToString().ToLowerInvariant() }
    else { throw "Unexpected native cleanup command: $Command $($Arguments -join ' ')" }
}
function Invoke-GithubApi {
    param([string] $Path, [string] $Method = 'GET', [object] $Body)
    if ($Path -eq 'repos/owner/adopter') { return [pscustomobject]@{ id = 99 } }
    if ($Path -eq 'repos/owner/adopter/actions/runners?per_page=100') {
        return [pscustomobject]@{ total_count = $script:runnerRecords.Count; runners = $script:runnerRecords }
    }
    if ($Method -eq 'DELETE') {
        $id = [long]($Path -split '/')[-1]
        $script:cleanupCalls += "delete-runner-$id"
        if ($script:runnerDeletionFailure) { throw 'Simulated GitHub runner deletion failure' }
        $script:runnerRecords = @($script:runnerRecords | Where-Object id -ne $id)
        return
    }
    throw "Unexpected cleanup API request: $Method $Path"
}
function Set-GithubVariable {
    param([string] $Repository, [string] $Name, [string] $Value, [string] $Environment)
    $script:cleanupCalls += "set-$Name-$Value"
}
function Assert-NoActiveReleaseRuns {
    param([string] $Repository)
    if ($script:activeReleaseFailure) { throw 'Simulated active release' }
}
try {
    Reset-CleanupTest
    Remove-AcceleratorResources $config $cleanupStateFile $true
    Assert-Test ([Array]::IndexOf($script:cleanupCalls, 'delete-azure') -lt [Array]::IndexOf($script:cleanupCalls, 'delete-runner-7')) 'Azure resources are deleted before the runner registration'
    Assert-Test (-not $script:azureGroupExists -and $script:runnerRecords.Count -eq 1 -and $script:runnerRecords[0].id -eq 8) 'Successful cleanup preserves unrelated runner registrations'
    $state = Get-Content -LiteralPath $cleanupStateFile -Raw | ConvertFrom-Json
    Assert-Test (-not $state.complete -and $null -eq $state.cleanup -and $state.deployment.runnerVm -eq 'vm-adopter') 'Successful cleanup clears its checkpoint while retaining deployment diagnostics'

    Reset-CleanupTest
    $script:azureDeletionFailure = $true
    Assert-Throws { Remove-AcceleratorResources $config $cleanupStateFile $true } 'blocked by lock' 'Azure deletion failure is explicit'
    Assert-Test ($script:runnerRecords.Count -eq 2 -and $script:cleanupCalls -notcontains 'delete-runner-7') 'Failed Azure deletion retains the usable runner registration'
    $state = Get-Content -LiteralPath $cleanupStateFile -Raw | ConvertFrom-Json
    Assert-Test ($state.cleanup.runnerIds.Count -eq 1 -and $state.cleanup.runnerIds[0] -eq 7) 'Cleanup checkpoints exact runner IDs before attempting Azure deletion'

    Reset-CleanupTest
    $script:azureDeletionPending = $true
    Assert-Throws { Remove-AcceleratorResources $config $cleanupStateFile $true } 'has not completed' 'Unconfirmed Azure deletion blocks runner removal'
    Assert-Test ($script:cleanupCalls -notcontains 'delete-runner-7') 'Pending Azure deletion leaves the registration intact'

    Reset-CleanupTest
    $script:runnerDeletionFailure = $true
    Assert-Throws { Remove-AcceleratorResources $config $cleanupStateFile $true } 'GitHub runner deletion failure' 'Post-Azure GitHub cleanup failure remains explicit'
    Assert-Test (-not $script:azureGroupExists -and $script:runnerRecords.Count -eq 2) 'Failed GitHub cleanup leaves a recoverable checkpoint after Azure deletion'
    $script:runnerDeletionFailure = $false
    $script:cleanupCalls = @()
    Remove-AcceleratorResources $config $cleanupStateFile $false
    Assert-Test ($script:cleanupCalls -notcontains 'delete-azure' -and $script:runnerRecords.Count -eq 1 -and $script:runnerRecords[0].id -eq 8) 'Retry finishes recorded runner cleanup when Azure group is already absent'

    Reset-CleanupTest
    $script:runnerDeletionFailure = $true
    Assert-Throws { Remove-AcceleratorResources $config $cleanupStateFile $true } 'GitHub runner deletion failure' 'Replacement-runner test creates a pending cleanup checkpoint'
    $script:runnerDeletionFailure = $false
    $script:runnerRecords = @(
        [pscustomobject]@{ id = 17; name = 'sql-99-adopter'; busy = $false },
        [pscustomobject]@{ id = 8; name = 'unrelated-runner'; busy = $false }
    )
    $script:cleanupCalls = @()
    Remove-AcceleratorResources $config $cleanupStateFile $false
    Assert-Test ($script:runnerRecords.Count -eq 2 -and $script:cleanupCalls -notcontains 'delete-runner-17') 'Retry never deletes a replacement runner just because its name matches'

    Reset-CleanupTest
    $script:azureDeletionFailure = $true
    Assert-Throws { Remove-AcceleratorResources $config $cleanupStateFile $true } 'blocked by lock' 'Mismatched-target test creates a cleanup checkpoint'
    $changed = $config.Clone()
    $changed.resourceGroupName = 'rg-another'
    $script:cleanupCalls = @()
    Assert-Throws { Remove-AcceleratorResources $changed $cleanupStateFile $false } 'another deployment' 'Cleanup retry refuses a different resource group'
    Assert-Test ($script:cleanupCalls.Count -eq 0) 'Mismatched retry does not mutate Azure or GitHub'

    Reset-CleanupTest
    Assert-Throws { Remove-AcceleratorResources $config $cleanupStateFile $false } 'No saved cleanup record' 'Absent Azure group cannot authorize deleting a runner by name'
    Assert-Test ($script:cleanupCalls.Count -eq 0) 'Unproven orphan ownership leaves GitHub settings and runners unchanged'
    $script:runnerRecords = @([pscustomobject]@{ id = 8; name = 'unrelated-runner'; busy = $false })
    Remove-AcceleratorResources $config $cleanupStateFile $false
    Assert-Test ($script:cleanupCalls.Count -eq 0) 'Already-clean deployment is an explicit no-op'

    Reset-CleanupTest
    $script:runnerRecords[0].busy = $true
    Assert-Throws { Remove-AcceleratorResources $config $cleanupStateFile $true } 'runner is busy' 'Busy runner blocks Azure and registration deletion'
    Assert-Test ($script:cleanupCalls.Count -eq 0) 'Busy-runner refusal does not change resources or release variables'
    Reset-CleanupTest
    $script:activeReleaseFailure = $true
    Assert-Throws { Remove-AcceleratorResources $config $cleanupStateFile $true } 'active release' 'Active release blocks both cleanup stages'
    Assert-Test ($script:cleanupCalls -notcontains 'delete-azure' -and $script:cleanupCalls -notcontains 'delete-runner-7') 'Active-release refusal retains Azure resources and registration'
}
finally {
    Set-Item -Path function:Invoke-CheckedCommand -Value $originalNative
    Set-Item -Path function:Invoke-GithubApi -Value $originalApi
    Set-Item -Path function:Set-GithubVariable -Value $originalVariable
    Set-Item -Path function:Assert-NoActiveReleaseRuns -Value $originalActiveGuard
    if (Test-Path -LiteralPath $cleanupStateFile) { Remove-Item -LiteralPath $cleanupStateFile }
}

Write-Host "$script:passed accelerator regression tests passed."
