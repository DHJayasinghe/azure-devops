$apiVersion = "7.1"

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
    
    $commitsUrl = "https://dev.azure.com/$organization/$project/_apis/git/repositories/$repository/commits?searchCriteria.itemVersion.version=$branchName&api-version=$apiVersion&searchCriteria.includeWorkItems=true&searchCriteria.fromDate=$fromDate&searchCriteria.$top=500"
    
    try {
        $response = Invoke-RestMethod -Uri $commitsUrl -Headers $headers -Method Get
        return $response.value
    }
    catch {
        Write-Host "Failed to fetch commits for branch: $branchName in repository: $repository"
        return @()
    }
}

function Get-BranchLastestCommitId {
    param (
        [string]$organization,
        [string]$project,
        [string]$repoName,
        [string]$branchName,
        [hashtable]$headers
    )
    $baseUrl = "https://dev.azure.com/$organization/$project/_apis/git/repositories/$($repoName)"

    
    $commitUrl = "$($baseUrl)/commits?searchCriteria.itemVersion.version=$branchName&`$top=1&api-version=$apiVersion"
    $commitResp = Invoke-RestMethod -Uri $commitUrl -Headers $headers -Method Get
    
    $commitId = $commitResp.value[0].commitId

    return $commitId
}

function Get-TagsForCommit {
    param (
        [string]$organization,
        [string]$project,
        [string]$repoName,
        [string]$tagPrefix,
        [string]$commitId,
        [hashtable]$headers
    )

    $baseUrl = "https://dev.azure.com/$organization/$project/_apis/git/repositories/$repoName"
    $tagsUrl = "$baseUrl/refs?filter=tags/$tagPrefix&api-version=$apiVersion"
    
    try {
        $tagsResponse = Invoke-RestMethod -Uri $tagsUrl -Headers $headers -Method Get
        $tags = $tagsResponse.value

        $matchingTags = @()
        foreach ($tag in $tags) {
            # Resolve the Tag commitId using the annotatedtags API
            $annotatedTagUrl = "$baseUrl/annotatedtags/$($tag.objectId)?api-version=$apiVersion"
            try {
                $tagCommitId = "NA"
                $annotatedTagResponse = Invoke-RestMethod -Uri $annotatedTagUrl -Headers $headers -Method Get
                $tagCommitId = $annotatedTagResponse.taggedObject.objectId
            } catch {
                $tagCommitId = "ERROR"
            }
            if ($tagCommitId -eq $commitId) {
                $matchingTags += $tag.name
            }
        }
        return $matchingTags
    }
    catch {
        Write-Host "Failed to fetch tags for repo: $repoName"
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

function Get-BranchLatestPipelineRuns {
    param (
        [string]$organization,
        [string]$project,
        [string]$branchName,
        [hashtable]$headers,
        [array]$pipelines,
        [string] $tagPrefix
    )
    $pendingRuns = @()
    $branchRef = if ($branchName -like 'refs/heads/*') { $branchName } else { "refs/heads/$branchName" }

    try {
        $pipelinesUrl = "https://dev.azure.com/$organization/$project/_apis/pipelines?api-version=$apiVersion"
        $allPipelines = Invoke-RestMethod -Uri $pipelinesUrl -Headers $headers -Method Get
        $filteredPipelines = $allPipelines.value | Where-Object {
            $pipelineName = $_.name
            $pipelines | Where-Object { $_.Name -eq $pipelineName }
        }

        foreach ($pipeline in $filteredPipelines) {
            $repoName = ($pipelines | Where-Object { $_.Name -eq $pipeline.name }).Repo

            $branchLatestCommitId = Get-BranchLastestCommitId -organization $organization -project $project -repoName $repoName -branchName $branchName -headers $headers
            $commitTags = Get-TagsForCommit -organization $organization -project $project -repoName $repoName -tagPrefix $tagPrefix -commitId $branchLatestCommitId -headers $headers 
            
            $branchHasReleaseTag = ($commitTags | Where-Object { $_ -like "refs/tags/$tagPrefix*" })

            if (-not $branchHasReleaseTag) {
                $buildsUrl = "https://dev.azure.com/$organization/$project/_apis/build/builds?definitions=$($pipeline.id)&branchName=$($branchRef)&api-version=$apiVersion"
                $buildsResponse = Invoke-RestMethod -Uri $buildsUrl -Headers $headers -Method Get

                $latestBuild = $buildsResponse.value |
                    Where-Object { $_.status -in @('completed', 'inProgress') } |
                    Sort-Object id -Descending |
                    Select-Object -First 1

                if ($latestBuild) {
                    $pendingRuns += [PSCustomObject]@{
                        PipelineId   = $pipeline.id
                        PipelineName = $pipeline.name
                        BuildId      = $latestBuild.id
                        CreatedDate  = $latestBuild.queueTime
                        BuildName    = $latestBuild.buildNumber
                        BuildUrl     = $latestBuild._links.web.href
                    }
                }
            }
        }

        return $pendingRuns
    }
    catch {
        Write-Host "❌ Failed to fetch pipeline runs: $_"
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
        Write-Host "✅ Deleted existing tag '$tagName'"
    }

    $commitId = Get-BranchLastestCommitId -organization $organization -project $project -repoName $repoName -branchName $branchName -headers $headers

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
    Write-Host "✅ Created tag '$tagName' with description '$description' on repo '$repoName'"
}
