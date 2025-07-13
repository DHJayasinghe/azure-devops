$pat = "jzX3ZYCiI1oMRuo6SA8IOCa9pq1Kmom2erp7eJsgFCfxg0CUO2tVJQQJ99BGACAAAAApUUOzAAASAZDO3GXk"
$targetBranch = "release/deployment-september-2025-sale"
$primaryReleaseTag = "sep-sale-25"
$newUATVersionTag = "#Release-Sep25-v2"
$newPRODVersionTag = "prd-20250714"

$organization = "Next-Technology"
$project = "Ecom.Sale"
$boardColumnField = "WEF_C20432DD5A1E4B66931BC16E0AC05E8C_Kanban.Column"
$repositories = @("ecm-sale-frontend")
$boardColumnMapping = @{
    "CI Testing" = "UAT Testing"
    "Default" = "Deployed to UAT"
}

$uatDeploymentPrep = $true
$prodDeploymentPrep = $false

if($uatDeploymentPrep)
{
    Write-Host "Starting UAT Deployment Preparation"

    Write-Host "Step 2 - Started Tagging Tickets & Moving to UAT Board Column"

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

    Write-Host "Step 1 - Started Tagging Tickets"
    .\tag-and-move-tickets-across-board.ps1 `
        -organization $organization `
        -project $project `
        -pat $pat `
        -targetBranch $targetBranch `
        -primaryReleaseTag $primaryReleaseTag `
        -newVersionTagPrefix "prd-" `
        -newVersionTag $newPRODVersionTag `
        -boardColumnField @{} `
        -repositories $repositories
}