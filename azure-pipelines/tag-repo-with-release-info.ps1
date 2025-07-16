param (
    [string]$organization,
    [string]$project,
    [string]$pat,
    [string]$repoName,
    [string]$branchName,
    [string]$tagPrefix,
    [string]$buildName,
    [string]$dropName,
    [string]$saleName,
    [array]$pipelines
)

. "$PSScriptRoot\Utility-Functions.ps1"

$headers = @{
    Authorization = ("Basic {0}" -f [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$pat")))
}

foreach ($pipeline in $pipelines) {
    if ($pipeline.Repo -ne "NA" -and $pipeline.BuildName -ne "NA") {
        $tagName = "$tagPrefix-$($pipeline.BuildName)"
        $description = "$dropName for $saleName"
        Set-RepoTag -organization $organization -project $project -repoName $pipeline.Repo -tagName $tagName -description $description -branchName $branchName -headers $headers
    }
}