$organization = "ORGANIZATION_NAME"
$project = "PROJECT_NAME"
$targetBranch = "refs/heads/BRANCH_NAME" 
$pat = "PAT_TOKEN"
$repositories = @("repo-backend", "repo-frontend")

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