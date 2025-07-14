# Decide before execute - IMPORTANT
$uatDeploymentPrep = $false
$prodDeploymentPrep = $true

# Change when expired - IMPORTANT
$pat = "PAT_TOKEN"

# Change during every release - IMPORTANT
$newUATVersionTag = "#Release-Sep25-v2"
$newPRODVersionTag = "prd-20250714"
$prodDropNumber = "Drop 1" # Suggestion - Instead repeating "Sep '25 Sale -" prefix for the query folders can we just use "All" & "Drop 1"? Main folder already got this prefix

# Change during every sale
$targetBranch = "release/deployment-september-2025-sale" # Suggestion - Can we standardize this to use the same $primaryReleaseTag? And Term "deployment" = "release/"
$primaryReleaseTag = "sep-sale-25"
$releaseQueryFolderName = "Test Automation" # Sep '25  # Suggestion - Can we standardize this to use the same $primaryReleaseTag?

# Constants
$organization = "Next-Technology"
$project = "Ecom.Sale"
$boardColumnField = "WEF_C20432DD5A1E4B66931BC16E0AC05E8C_Kanban.Column"
$repositories = @("ecm-sale-frontend")
# $repositories = @("ecm-sale-frontend","ecm-sale-admin","ecm-sale-admin-frontend","ecm-vip-searchfeed","ecm-sale-mainframe-agents","ecm-sale-session-agents","ecm-sale-payments-agents")
$pipelines = @(
    @{ Name = "ecm-sale-web"; Repo = "ecm-sale-frontend" },
    @{ Name = "ecm-sale-search-service"; Repo = "" },
    @{ Name = "ecm-sale-admin-deploy"; Repo = "ecm-sale-admin" },
    @{ Name = "ecm-sale-admin-frontend"; Repo = "ecm-sale-admin-frontend" },
    @{ Name = "ecm-vip-searchfeed"; Repo = "ecm-vip-searchfeed" },
    @{ Name = "ecm-sale-mainframe-agents-deploy"; Repo = "ecm-sale-mainframe-agents" },
    @{ Name = "ecm-sale-session-agents-deploy"; Repo = "ecm-sale-session-agents" },
    @{ Name = "ecm-sale-payments-agents-deploy"; Repo = "ecm-sale-payments-agents" }
)
$boardColumnMapping = @{
    "CI Testing" = "UAT Testing"
    "Default" = "Deployed to UAT"
}
$releaseQueryProjectName = "OnlineTech.Backlog"
$releaseQueryFolderPath = "Shared Queries/Sale/Releases"
$changeRequestSearchPrefix = "Create New ServiceNow Change Request"


if($uatDeploymentPrep)
{
    Write-Host "Starting UAT Deployment Preparation"

    Write-Host "Step 2 - Tagging for UAT Release & Moving across the Board"

    .\tag-and-move-tickets-across-board.ps1 `
        -organization $organization `
        -project $project `
        -pat $pat `
        -targetBranch $targetBranch `
        -primaryReleaseTag $primaryReleaseTag `
        -newVersionTagPrefix "#Release-" `
        -newVersionTag $newUATVersionTag `
        -boardColumnField $boardColumnField `
        -repositories $repositories `
        -columnMapping $boardColumnMapping
}

if($prodDeploymentPrep)
{
    Write-Host "Starting PROD Deployment Preparation"

    Write-Host "Step 1 - Tagging for Prod Release"
    # .\tag-and-move-tickets-across-board.ps1 `
    #     -organization $organization `
    #     -project $project `
    #     -pat $pat `
    #     -targetBranch $targetBranch `
    #     -primaryReleaseTag $primaryReleaseTag `
    #     -newVersionTagPrefix "prd-" `
    #     -newVersionTag $newPRODVersionTag `
    #     -boardColumnField @{} `
    #     -repositories $repositories

    Write-Host "Step 2 - Creating Board Queries"

    # .\create-board-query-for-release.ps1 `
    #     -organization $organization `
    #     -project $releaseQueryProjectName  `
    #     -pat $pat `
    #     -folderPath $releaseQueryFolderPath `
    #     -targetFolderName $releaseQueryFolderName `
    #     -tag $newPRODVersionTag `
    #     -queriesToCreate @(
    #         @{ Name = "All"; Mode = "Merge" }, 
    #         @{ Name = $prodDropNumber; Mode = "Replace" }
    #     )

    Write-Host "Step 3 - Extracting Release Information"

    $pipelineNames = $pipelines | ForEach-Object { $_.Name }

    Write-Host $pipelineNames

    $result = .\extract-release-information.ps1 `
        -organization $organization `
        -project $project  `
        -pat $pat `
        -targetBranch $targetBranch `
        -changeRequestSearchPrefix $changeRequestSearchPrefix `
        -pipelines $pipelineNames

    $parsed = $result | ConvertFrom-Json
    foreach ($item in $parsed) {
        Write-Host "Pipeline: $($item.PipelineName), BuildName: $($item.BuildName)"
    }
}