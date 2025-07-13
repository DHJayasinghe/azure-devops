param (
    [string]$organization,
    [string]$project,
    [string]$pat,
    [string]$targetBranch,
    [string]$changeRequestSearchPrefix
)

. "$PSScriptRoot\Utility-Functions.ps1"

$headers = @{
    Authorization = ("Basic {0}" -f [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$pat")))
}

function ExtractChangeRequestNumber {
    param (
        [int]$buildId
    )

    $timelineUrl = "https://dev.azure.com/$organization/$project/_apis/build/builds/$buildId/timeline?api-version=7.1"
    
    try {
        $timeline = Invoke-RestMethod -Uri $timelineUrl -Headers $headers -Method Get
    }
    catch {
        Write-Warning "❌ Failed to fetch timeline for build $buildId"
        return "NA"
    }

    $targetStep = $timeline.records | Where-Object {
        $_.name -eq $changeRequestSearchPrefix -and $_.type -eq "Task"
    }

    if (-not $targetStep) {
        Write-Warning "⚠️ Step '$($changeRequestSearchPrefix)' not found in build $buildId"
        return "NA"
    }

    $logUrl = $targetStep.log.url

    try {
        $logContent = Invoke-RestMethod -Uri $logUrl -Headers $headers -Method Get
    }
    catch {
        Write-Warning "❌ Failed to fetch log content for build $buildId"
        return "NA"
    }

    $chgMatches = Select-String -InputObject $logContent -Pattern '\bCHG\d+\b' -AllMatches
    $chgId = ($chgMatches.Matches | ForEach-Object { $_.Value } | Select-Object -First 1)

    return $chgId
}

# After processing tickets, find and approve pending pipeline runs
Write-Output "========================================="
Write-Output "Checking for pending pipeline runs..."

$pendingRuns = Get-PendingPipelineRuns -organization $organization -project $project -branchName $targetBranch -headers $headers

# Create output file path
$outputFile = "Release-Note-Info-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"

if ($pendingRuns.Count -gt 0) {
    Write-Output "Found $($pendingRuns.Count) pending pipeline runs. Extracting release info..."
    
    # Write header to file
    "PipelineName,BuildName,ChangeRequest #,BuildUrl" | Out-File -FilePath $outputFile -Encoding UTF8
    
    foreach ($run in $pendingRuns) {
        $chgId = ExtractChangeRequestNumber -buildId $run.BuildId

        # Write-Output "Pipeline: $($run.PipelineName) (ID: $($run.PipelineId))"
        # Write-Output "Build ID: $($run.BuildId)"
        # Write-Output "Build Name: $($run.BuildName)"
        # Write-Output "Build URL: $($run.BuildUrl)"
        # Write-Output "Change Request #: $($chgId)"
        
        # Write-Output "---"
        
        # Write data to file in CSV format
        "$($run.PipelineName),$($run.BuildName),$($chgId),$($run.BuildUrl)" | Out-File -FilePath $outputFile -Append -Encoding UTF8
    }
    
    Write-Output "Pipeline information has been saved to: $outputFile"
}
else {
    Write-Output "No pending pipeline runs found for branch $targetBranch"
}

