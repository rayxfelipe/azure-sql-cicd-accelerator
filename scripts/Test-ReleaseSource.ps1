[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $Repository,
    [Parameter(Mandatory)][string] $SourceRunId
)

. (Join-Path $PSScriptRoot 'Common.ps1')
if ($SourceRunId -notmatch '^[1-9]\d*$') { throw 'Run ID must be a positive integer.' }
$run = Invoke-GithubApi "repos/$Repository/actions/runs/$SourceRunId"
$jobs = Invoke-GithubApi "repos/$Repository/actions/runs/$SourceRunId/jobs?filter=latest&per_page=100"
$artifacts = Invoke-GithubApi "repos/$Repository/actions/runs/$SourceRunId/artifacts?per_page=100"
if ($jobs.total_count -gt 100 -or $artifacts.total_count -gt 100) { throw 'Unexpected source run size; cannot safely validate a truncated API response.' }
$artifact = Assert-TrustedRelease $run $jobs.jobs $artifacts.artifacts $Repository
"run-id=$SourceRunId" >> $env:GITHUB_OUTPUT
"artifact-id=$($artifact.id)" >> $env:GITHUB_OUTPUT
"Promoting commit $($run.head_sha) from run $SourceRunId, artifact $($artifact.id)." >> $env:GITHUB_STEP_SUMMARY
