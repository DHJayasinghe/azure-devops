$organization = "ORGANIZATION_NAME"
$project = "PROJECT_NAME"
$targetBranch = "refs/heads/BRANCH_NAME" 
$pat = "PAT_TOKEN"
$repositories = @("repo-backend", "repo-frontend")
$newReleaseTag = "#Release-July25-v3"

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
        [string]$newReleaseTag
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
        $updatedTags = $newReleaseTag
    }
    else {
        $updatedTags = "$existingTags; $newReleaseTag"
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
        Write-Host "✅ Added $newReleaseTag to Ticket $ticketId."
    }
    catch {
        Write-Host "❌ Failed to update Ticket $ticketId. Error: $_"
    }
}


foreach ($ticketId in $distinctTicketIds) {
    $canAddReleaseTag = Has-ReleaseTag -organization $organization -project $project -ticketId $ticketId -headers $headers -primaryReleaseTag $primaryReleaseTag

    if ($canAddReleaseTag) {
        Write-Host "✅ Ticket $ticketId has $primaryReleaseTag but no #Release- tag."
    }
}