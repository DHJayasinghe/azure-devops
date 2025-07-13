

$uatDeploymentPrep = $true
$prodDeploymentPrep = $false

if($uatDeploymentPrep)
{
    Write-Host "Starting UAT Deployment Preparation"

    Write-Host "Step 2 - Started Tagging Tickets & Moving to UAT Board Column"

    .\tag-tickets-and-move-to-uat.ps1 `
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
    .\tag-tickets-and-move-to-uat.ps1 `
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