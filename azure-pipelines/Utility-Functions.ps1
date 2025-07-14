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
    
    $commitsUrl = "https://dev.azure.com/$organization/$project/_apis/git/repositories/$repository/commits?searchCriteria.itemVersion.version=$branchName&api-version=7.1&searchCriteria.includeWorkItems=true&searchCriteria.fromDate=$fromDate&searchCriteria.$top=500"
    
    try {
        $response = Invoke-RestMethod -Uri $commitsUrl -Headers $headers -Method Get
        return $response.value
    }
    catch {
        Write-Host "Failed to fetch commits for branch: $branchName in repository: $repository"
        return @()
    }
}

function Has-ReleaseTag {
    param (
        [string]$organization,
        [string]$project,
        [string]$ticketId,
        [hashtable]$headers,
        [string]$primaryReleaseTag,
        [string]$tagPrefix
    )

    $workItemUrl = "https://dev.azure.com/$organization/$project/_apis/wit/workitems/${ticketId}?api-version=7.1-preview.3"

    try {
        $workItemResponse = Invoke-RestMethod -Uri $workItemUrl -Headers $headers -Method Get
    }
    catch {
        Write-Host "Failed to fetch work item: $ticketId. Error: $_"
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
        if ($tag.StartsWith($tagPrefix)) {
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
        [hashtable]$headers,
        [hashtable]$columnMapping
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

    $columnField = $boardColumnField
    $currentColumn = $workItemResponse.fields.$columnField

    Write-Host "📌 Current Kanban Column: $currentColumn"

    # Check if current column exists in the mapping
    if ($columnMapping.ContainsKey($currentColumn)) {
        $newColumn = $columnMapping[$currentColumn]
    }
    else {
        $newColumn = $columnMapping['Default']
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

function Get-LinkedTicketIdsFromRepos {
    param (
        [string]$organization,
        [string]$project,
        [string[]]$repositories,
        [string]$targetBranch,
        [hashtable]$headers
    )

    $allTicketIds = @()

    foreach ($repository in $repositories) {
        Write-Host "Processing repository: $repository"

        $commits = Get-BranchCommits -organization $organization -project $project -repository $repository -branchName $targetBranch -headers $headers
        
        Write-Host "Found $($commits.Count) commits in branch $targetBranch"
        
        foreach ($commit in $commits) {
            $ticketIds = $commit.workItems | ForEach-Object { $_.id }
            $allTicketIds += $ticketIds
        }
    }
    $distinctTicketIds = $allTicketIds | Sort-Object -Unique
    return $distinctTicketIds
}

function Get-LatestPipelineRuns {
    param (
        [string]$organization,
        [string]$project,
        [string]$branchName,
        [hashtable]$headers,
        [array]$pipelines
    )

    $pipelinesUrl = "https://dev.azure.com/$organization/$project/_apis/pipelines?api-version=7.1"
    
    try {
        $allPipelines = Invoke-RestMethod -Uri $pipelinesUrl -Headers $headers -Method Get
        $pendingRuns = @()

        foreach ($pipeline in $allPipelines.value) {
            if ($pipelines -contains $pipeline.name) 
            {
                $runsUrl = "https://dev.azure.com/$organization/$project/_apis/pipelines/$($pipeline.id)/runs?api-version=7.1&branchName=$($branchName)"
                
                $runs = Invoke-RestMethod -Uri $runsUrl -Headers $headers -Method Get

                # Get the latest run that needs approval
                $latestPendingRun = $runs.value | 
                    # Where-Object { $_.state -eq 'inProgress' } | 
                    Sort-Object createdDate -Descending | 
                    Select-Object -First 1

                if ($latestPendingRun) {
                    $pendingRuns += [PSCustomObject]@{
                        PipelineId = $pipeline.id
                        PipelineName = $pipeline.name
                        BuildId = $latestPendingRun.id
                        CreatedDate = $latestPendingRun.createdDate
                        BuildName = $latestPendingRun.name
                        BuildUrl = "https://dev.azure.com/$organization/$project/_build/results?buildId=$($latestPendingRun.id)"
                    }
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

    $approveUrl = "https://dev.azure.com/$organization/$project/_apis/pipelines/$pipelineId/runs/$runId/approve?api-version=7.1"
    
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

function Set-RepoTag {
    param (
        [string]$organization,
        [string]$project,
        [string]$repoName,
        [string]$branchName,
        [string]$tagName,
        [string]$description,
        [hashtable]$headers
    )

    # Base URLs
    $baseUrl = "https://dev.azure.com/$organization/$project/_apis/git/repositories/$repoName"
    $apiVersion = "7.1"

    # Check if tag exists
    $checkTagUrl = "$baseUrl/refs?filter=tags/$tagName&api-version=$apiVersion"
    $existingTag = Invoke-RestMethod -Uri $checkTagUrl -Headers $headers -Method Get

    if ($existingTag.count -gt 0 -and $existingTag.value.Count -gt 0) {
        # Delete existing tag using special zeroed ObjectId
        $deleteTagUrl = "$baseUrl/refs?api-version=$apiVersion"
        $oldObjectId = $existingTag.value[0].objectId

        $deleteBody = @(
            @{
                name         = "refs/tags/$($tagName)"
                oldObjectId  = $oldObjectId
                newObjectId  = "0000000000000000000000000000000000000000"
            }
        ) | ConvertTo-Json -Depth 5

        $deleteBody = "[$deleteBody]"

        Invoke-RestMethod -Uri $deleteTagUrl -Headers $headers -Method Post -Body $deleteBody -ContentType "application/json" > $null
        Write-Host "Deleted existing tag '$tagName'"
    }

    # Get the latest commit ID on the given branch
    $commitUrl = "$baseUrl/commits?searchCriteria.itemVersion.version=$branchName&`$top=1&api-version=$apiVersion"
    $commitResp = Invoke-RestMethod -Uri $commitUrl -Headers $headers -Method Get
    $commitId = $commitResp.value[0].commitId

    # Create the annotated tag
    $createTagUrl = "$baseUrl/annotatedtags?api-version=$apiVersion"
    $tagBody = @{
        name         = $tagName
        taggedObject = @{
            objectId   = $commitId
            objectType = "commit"
        }
        message      = $description
    } | ConvertTo-Json -Depth 5

    Invoke-RestMethod -Uri $createTagUrl -Headers $headers -Method Post -Body $tagBody -ContentType "application/json" > $null
    Write-Host "Created tag '$tagName' with description '$description' on repo '$repoName'"
}
