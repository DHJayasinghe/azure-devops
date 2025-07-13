Write-Host "Step 2 - Started Tagging Tickets & Moving to UAT Board Column"
.\tag-tickets-and-move-to-uat.ps1 `
    -organization $organization `
    -project $project `
    -pat $pat `
    -targetBranch $targetBranch `
    -primaryReleaseTag $primaryReleaseTag `
    -newVersionTag $newVersionTag `
    -boardColumnField $boardColumnField `
    -repositories $repositories