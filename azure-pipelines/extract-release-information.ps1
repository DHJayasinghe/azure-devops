param (
    [string]$organization,
    [string]$project,
    [string]$pat,
    [string]$targetBranch,
    [string]$changeRequestSearchPrefix,
    [array]$pipelines
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
Write-Host "========================================="
Write-Host "Checking for pending pipeline runs..."

$pendingRuns = Get-LatestPipelineRuns -organization $organization -project $project -branchName $targetBranch -headers $headers -pipelines $pipelines

# Create output file path
$outputFile = "Release-Note-Info-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
$pipelineResults = @()

if ($pendingRuns.Count -gt 0) {
    Write-Host "Found $($pendingRuns.Count) pending pipeline runs. Extracting release info..."
    
    # Write header to file
    "PipelineName,BuildName,ChangeRequest #,BuildUrl" | Out-File -FilePath $outputFile -Encoding UTF8
    
    foreach ($run in $pendingRuns) {
        $chgId = ExtractChangeRequestNumber -buildId $run.BuildId

        $pipelineResults += [PSCustomObject]@{
            PipelineName = $run.PipelineName
            BuildName      = $run.BuildName
        }
        # Write-Host "Pipeline: $($run.PipelineName) (ID: $($run.PipelineId))"
        # Write-Host "Build ID: $($run.BuildId)"
        # Write-Host "Build Name: $($run.BuildName)"
        # Write-Host "Build URL: $($run.BuildUrl)"
        # Write-Host "Change Request #: $($chgId)"
        
        # Write-Host "---"
        
        # Write data to file in CSV format
        "$($run.PipelineName),$($run.BuildName),$($chgId),$($run.BuildUrl)" | Out-File -FilePath $outputFile -Append -Encoding UTF8
    }
    
    Write-Host "Pipeline information has been saved to: $outputFile"
}
else {
    Write-Host "No pending pipeline runs found for branch $targetBranch"
}

if ($pipelineResults.Count -gt 0) {
    # Return as JSON for easy consumption
    $pipelineResults | ConvertTo-Json -Depth 3
}

