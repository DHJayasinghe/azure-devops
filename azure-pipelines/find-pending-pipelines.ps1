function Get-PendingPipelineRuns {
    param (
        [string]$organization,
        [string]$project,
        [string]$branchName,
        [hashtable]$headers
    )

    $pipelinesUrl = "https://dev.azure.com/$organization/$project/_apis/pipelines?api-version=7.1-preview.1"
    
    try {
        $pipelines = Invoke-RestMethod -Uri $pipelinesUrl -Headers $headers -Method Get
        $pendingRuns = @()

        foreach ($pipeline in $pipelines.value) {
            $runsUrl = "https://dev.azure.com/$organization/$project/_apis/pipelines/$($pipeline.id)/runs?api-version=7.1-preview.1&branchName=$branchName"
            $runs = Invoke-RestMethod -Uri $runsUrl -Headers $headers -Method Get

            # Get the latest run that needs approval
            $latestPendingRun = $runs.value | 
                Where-Object { $_.state -eq 'inProgress' -and $_.result -eq 'none' } | 
                Sort-Object createdDate -Descending | 
                Select-Object -First 1

            if ($latestPendingRun) {
                $pendingRuns += [PSCustomObject]@{
                    PipelineId = $pipeline.id
                    PipelineName = $pipeline.name
                    RunId = $latestPendingRun.id
                    CreatedDate = $latestPendingRun.createdDate
                }
            }
        }

        return $pendingRuns
    }
    catch {
        Write-Host "Failed to fetch pipeline runs: $_"
        return @()
    }
}

function Approve-PipelineRun {
    param (
        [string]$organization,
        [string]$project,
        [int]$pipelineId,
        [int]$runId,
        [hashtable]$headers
    )

    $approveUrl = "https://dev.azure.com/$organization/$project/_apis/pipelines/$pipelineId/runs/$runId/approve?api-version=7.1-preview.1"
    
    try {
        $body = @{
            status = "approved"
            comment = "Auto-approved by release tagging script"
        } | ConvertTo-Json

        Invoke-RestMethod -Uri $approveUrl -Headers $headers -Method Post -Body $body -ContentType "application/json"
        Write-Host "✅ Approved pipeline run $runId for pipeline $pipelineId"
        return $true
    }
    catch {
        Write-Host "❌ Failed to approve pipeline run $runId for pipeline $pipelineId : $_"
        return $false
    }
}

# After processing tickets, find and approve pending pipeline runs
Write-Output "========================================="
Write-Output "Checking for pending pipeline runs..."

$pendingRuns = Get-PendingPipelineRuns -organization $organization -project $project -branchName $targetBranch -headers $headers

if ($pendingRuns.Count -gt 0) {
    Write-Output "Found $($pendingRuns.Count) pending pipeline runs:"
    foreach ($run in $pendingRuns) {
        Write-Output "Pipeline: $($run.PipelineName) (ID: $($run.PipelineId))"
        Write-Output "Run ID: $($run.RunId)"
        Write-Output "Created: $($run.CreatedDate)"
        Write-Output "---"
        
        # Approve-PipelineRun -organization $organization -project $project -pipelineId $run.PipelineId -runId $run.RunId -headers $headers > $null
    }
}
else {
    Write-Output "No pending pipeline runs found for branch $targetBranch"
}