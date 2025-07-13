# $organization = "ORGANIZATION_NAME"
# $project = "PROJECT_NAME"

# $pat = "PAT_TOKEN"
# $targetBranch = "release/BRANCH_NAME" 
# $primaryReleaseTag = "july-sale-25"
# $newVersionTag = "#Release-July25-v3"

# $repositories = @("repo-backend", "repo-frontend")

$primaryReleaseTag = "sep-sale-25"
$newVersionTag = "#Release-Sep25-v2"

# $repositories = @("ecm-sale-frontend", "ecm-sale-admin", "ecm-sale-admin-frontend", "ecm-sale-mainframe-agents", "ecm-sale-payments-agents", "ecm-sale-session-agents", "ecm-vip-searchfeed")
$repositories = @("ecm-sale-frontend")

# Encode PAT for Basic Auth
$headers = @{
    Authorization = ("Basic {0}" -f [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$pat")))
}

$allTicketIds = @()

function Get-BranchCommits {
    param (
        [string]$organization,
        [string]$project,
        [string]$repository,
        [string]$branchName,
        [hashtable]$headers
    )

    # Get current year and set the start date to January 1st of current year
    $currentYear = (Get-Date).Year
    $fromDate = "$currentYear-01-01T00:00:00Z"
    
    $commitsUrl = "https://dev.azure.com/$organization/$project/_apis/git/repositories/$repository/commits?searchCriteria.itemVersion.version=$branchName&api-version=7.1-preview.1&searchCriteria.includeWorkItems=true&searchCriteria.fromDate=$fromDate&searchCriteria.$top=500"
    
    try {
        $response = Invoke-RestMethod -Uri $commitsUrl -Headers $headers -Method Get
        return $response.value
    }
    catch {
        Write-Host "Failed to fetch commits for branch: $branchName in repository: $repository"
        return @()
    }
}

# Loop through each repository
foreach ($repository in $repositories) {
    Write-Output "Processing repository: $repository"

    # Get all commits from the target branch
    $commits = Get-BranchCommits -organization $organization -project $project -repository $repository -branchName $targetBranch -headers $headers
    
    Write-Output "Found $($commits.Count) commits in branch $targetBranch"

    # Process each commit
    foreach ($commit in $commits) {
        # Get work items directly from the commit object
        $ticketIds = $commit.workItems | ForEach-Object { $_.id }
        $allTicketIds += $ticketIds
    }
}

# Step 3: Get distinct Ticket IDs
$distinctTicketIds = $allTicketIds | Sort-Object -Unique

# Output
Write-Output "========================================="
Write-Output "All Linked Ticket IDs (Distinct across repositories):"
$distinctTicketIds

Write-Output "========================================="
Write-Output "Checking #Release- tags on each ticket..."

function Has-ReleaseTag {
    param (
        [string]$organization,
        [string]$project,
        [string]$ticketId,
        [hashtable]$headers,
        [string]$primaryReleaseTag
    )

    $workItemUrl = "https://dev.azure.com/$organization/$project/_apis/wit/workitems/${ticketId}?api-version=7.1-preview.3"

    try {
        $workItemResponse = Invoke-RestMethod -Uri $workItemUrl -Headers $headers -Method Get
    }
    catch {
        Write-Host "Failed to fetch work item: $ticketId"
        return $false
    }

    $tagsString = $workItemResponse.fields.'System.Tags'

    if ($null -eq $tagsString) {
        return $false
    }

    $tags = $tagsString -split ';'
    $hasPrimaryTag = $false
    $hasReleaseTag = $false

    foreach ($tag in $tags) {
        $tag = $tag.Trim()
        if ($tag -eq $primaryReleaseTag) {
            $hasPrimaryTag = $true
        }
        if ($tag.StartsWith("#Release-")) {
            $hasReleaseTag = $true
        }
    }

    # Return true if it has the primary tag but no release tag
    return $hasPrimaryTag -and -not $hasReleaseTag
}

function Add-ReleaseTag {
    param (
        [string]$organization,
        [string]$project,
        [string]$ticketId,
        [hashtable]$headers,
        [string]$newVersionTag
    )

    $workItemUrl = "https://dev.azure.com/$organization/$project/_apis/wit/workitems/${ticketId}?api-version=7.1-preview.3"

    Write-Host $workItemUrl

    try {
        $workItemResponse = Invoke-RestMethod -Uri $workItemUrl -Headers $headers -Method Get
    }
    catch {
        Write-Host "Failed to fetch work item: $ticketId"
        return
    }

    $existingTags = $workItemResponse.fields.'System.Tags'

    if ($null -eq $existingTags) {
        $updatedTags = $newVersionTag
    }
    else {
        $updatedTags = "$existingTags; $newVersionTag"
    }

    Write-Host "New Tag(s) to be added: $updatedTags"

    # Prepare Patch body
    
    $data = @()

    $data += [PSCustomObject]@{
        op    = "add"
        path  = "/fields/System.Tags"
        value = $updatedTags
    }

    if ($data.Count -eq 1) {
        $body = "[" + ($data | ConvertTo-Json -Depth 10 -Compress) + "]"
    }
    else {
        $body = ($data | ConvertTo-Json -Depth 10 -Compress)
    }

    try {
        Invoke-RestMethod -Uri $workItemUrl -Headers $headers -Method Patch -Body $body -ContentType "application/json-patch+json"
        Write-Host "✅ Added $newVersionTag to Ticket $ticketId."
    }
    catch {
        Write-Host "❌ Failed to update Ticket $ticketId. Error: $_"
    }
}

function Update-KanbanColumn {
    param (
        [string]$organization,
        [string]$project,
        [string]$ticketId,
        [hashtable]$headers
    )

    $workItemUrl = "https://dev.azure.com/$organization/$project/_apis/wit/workitems/${ticketId}?api-version=7.1-preview.3"
    Write-Host "🔍 Fetching work item from: $workItemUrl"

    try {
        $workItemResponse = Invoke-RestMethod -Uri $workItemUrl -Headers $headers -Method Get
    }
    catch {
        Write-Host "❌ Failed to fetch work item: $ticketId"
        return
    }

    $columnField = 'WEF_C20432DD5A1E4B66931BC16E0AC05E8C_Kanban.Column'
    $currentColumn = $workItemResponse.fields.$columnField

    Write-Host "📌 Current Kanban Column: $currentColumn"

    if ($currentColumn -eq "CI Testing") {
        $newColumn = "UAT Testing"
    }
    else {
        $newColumn = "Deployed to UAT"
    }

    Write-Host "🔄 Updating Kanban column to: $newColumn"

    $data = @(
        [PSCustomObject]@{
            op    = "add"
            path  = "/fields/$columnField"
            value = $newColumn
        }
    )

    if ($data.Count -eq 1) {
        $body = "[" + ($data | ConvertTo-Json -Depth 10 -Compress) + "]"
    }
    else {
        $body = ($data | ConvertTo-Json -Depth 10 -Compress)
    }

    try {
        Invoke-RestMethod -Uri $workItemUrl -Headers $headers -Method Patch -Body $body -ContentType "application/json-patch+json"
        Write-Host "✅ Kanban column updated to '$newColumn' for Ticket $ticketId."
    }
    catch {
        Write-Host "❌ Failed to update Kanban column for Ticket $ticketId. Error: $_"
    }
}

foreach ($ticketId in $distinctTicketIds) {
    $canAddReleaseTag = Has-ReleaseTag -organization $organization -project $project -ticketId $ticketId -headers $headers -primaryReleaseTag $primaryReleaseTag

    if ($canAddReleaseTag) {
        Write-Host "✅ Ticket $ticketId has $primaryReleaseTag but no #Release- tag."
        Add-ReleaseTag -organization $organization -project $project -ticketId $ticketId -headers $headers -newVersionTag $newVersionTag > $null
        Update-KanbanColumn -organization $organization -project $project -ticketId $ticketId -headers $headers > $null
   }
}

# function Get-PendingPipelineRuns {
#     param (
#         [string]$organization,
#         [string]$project,
#         [string]$branchName,
#         [hashtable]$headers
#     )

#     $pipelinesUrl = "https://dev.azure.com/$organization/$project/_apis/pipelines?api-version=7.1-preview.1"
    
#     try {
#         $pipelines = Invoke-RestMethod -Uri $pipelinesUrl -Headers $headers -Method Get
#         $pendingRuns = @()

#         foreach ($pipeline in $pipelines.value) {
#             $runsUrl = "https://dev.azure.com/$organization/$project/_apis/pipelines/$($pipeline.id)/runs?api-version=7.1-preview.1&branchName=$branchName"
#             $runs = Invoke-RestMethod -Uri $runsUrl -Headers $headers -Method Get

#             # Get the latest run that needs approval
#             $latestPendingRun = $runs.value | 
#                 Where-Object { $_.state -eq 'inProgress' -and $_.result -eq 'none' } | 
#                 Sort-Object createdDate -Descending | 
#                 Select-Object -First 1

#             if ($latestPendingRun) {
#                 $pendingRuns += [PSCustomObject]@{
#                     PipelineId = $pipeline.id
#                     PipelineName = $pipeline.name
#                     RunId = $latestPendingRun.id
#                     CreatedDate = $latestPendingRun.createdDate
#                 }
#             }
#         }

#         return $pendingRuns
#     }
#     catch {
#         Write-Host "Failed to fetch pipeline runs: $_"
#         return @()
#     }
# }

# function Approve-PipelineRun {
#     param (
#         [string]$organization,
#         [string]$project,
#         [int]$pipelineId,
#         [int]$runId,
#         [hashtable]$headers
#     )

#     $approveUrl = "https://dev.azure.com/$organization/$project/_apis/pipelines/$pipelineId/runs/$runId/approve?api-version=7.1-preview.1"
    
#     try {
#         $body = @{
#             status = "approved"
#             comment = "Auto-approved by release tagging script"
#         } | ConvertTo-Json

#         Invoke-RestMethod -Uri $approveUrl -Headers $headers -Method Post -Body $body -ContentType "application/json"
#         Write-Host "✅ Approved pipeline run $runId for pipeline $pipelineId"
#         return $true
#     }
#     catch {
#         Write-Host "❌ Failed to approve pipeline run $runId for pipeline $pipelineId : $_"
#         return $false
#     }
# }

# # After processing tickets, find and approve pending pipeline runs
# Write-Output "========================================="
# Write-Output "Checking for pending pipeline runs..."

# $pendingRuns = Get-PendingPipelineRuns -organization $organization -project $project -branchName $targetBranch -headers $headers

# if ($pendingRuns.Count -gt 0) {
#     Write-Output "Found $($pendingRuns.Count) pending pipeline runs:"
#     foreach ($run in $pendingRuns) {
#         Write-Output "Pipeline: $($run.PipelineName) (ID: $($run.PipelineId))"
#         Write-Output "Run ID: $($run.RunId)"
#         Write-Output "Created: $($run.CreatedDate)"
#         Write-Output "---"
        
#         # Approve-PipelineRun -organization $organization -project $project -pipelineId $run.PipelineId -runId $run.RunId -headers $headers > $null
#     }
# }
# else {
#     Write-Output "No pending pipeline runs found for branch $targetBranch"
# }