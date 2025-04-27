# $organization = "ORGANIZATION_NAME"
# $project = "PROJECT_NAME"
# $targetBranch = "refs/heads/BRANCH_NAME" 
# $pat = "PAT_TOKEN"
# $repositories = @("repo-backend", "repo-frontend")

# Encode PAT for Basic Auth
$headers = @{
    Authorization = ("Basic {0}" -f [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$pat")))
}

$allTicketIds = @()

# Loop through each repository
foreach ($repository in $repositories) {
    Write-Output "Processing repository: $repository"

    # Step 1: Get the latest pull request targeting the branch
    $pullsUrl = "https://dev.azure.com/$organization/$project/_apis/git/repositories/$repository/pullRequests?searchCriteria.targetRefName=$($targetBranch)&`$top=1&searchCriteria.status=all&api-version=7.1-preview.1"

    try {
        $response = Invoke-RestMethod -Uri $pullsUrl -Headers $headers -Method Get
    }
    catch {
        Write-Host "Failed to fetch PRs for repository: $repository"
        continue
    }

    if ($response.count -eq 0) {
        Write-Host "No pull requests found targeting $targetBranch in $repository."
        continue
    }

    $latestPR = $response.value | Sort-Object creationDate -Descending | Select-Object -First 1
    $pullRequestId = $latestPR.pullRequestId

    Write-Output " -> Latest PR ID: $pullRequestId"

    # Step 2: Fetch linked work items for this PR
    $workitemsUrl = "https://dev.azure.com/$organization/$project/_apis/git/repositories/$repository/pullRequests/$pullRequestId/workitems?api-version=7.1-preview.1"

    try {
        $workitemsResponse = Invoke-RestMethod -Uri $workitemsUrl -Headers $headers -Method Get
    }
    catch {
        Write-Host "Failed to fetch work items for PR: $pullRequestId in $repository"
        continue
    }

    $ticketIds = $workitemsResponse.value | ForEach-Object { $_.id }

    # Add to the big array
    $allTicketIds += $ticketIds
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
        [hashtable]$headers
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

    foreach ($tag in $tags) {
        if ($tag.Trim().StartsWith("#Release-")) {
            return $true
        }
    }

    return $false
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

    Write-Host "Patch Body: $body"

    try {
        Invoke-RestMethod -Uri $workItemUrl -Headers $headers -Method Patch -Body $body -ContentType "application/json-patch+json"
        Write-Host "✅ Added $newReleaseTag to Ticket $ticketId."
    }
    catch {
        Write-Host "❌ Failed to update Ticket $ticketId. Error: $_"
    }
}


foreach ($ticketId in $distinctTicketIds) {
    $hasReleaseTag = Has-ReleaseTag -organization $organization -project $project -ticketId $ticketId -headers $headers

    if ($hasReleaseTag) {
        Write-Host "✅ Ticket $ticketId already has a #Release- tag."
    }
    else {
        Write-Host "❌ Ticket $ticketId does NOT have a #Release- tag."
        # Add-ReleaseTag -organization $organization -project $project -ticketId $ticketId -headers $headers -newReleaseTag $newReleaseTag
    }
}