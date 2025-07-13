param (
    [string]$organization,
    [string]$project,
    [string]$pat,
    [string]$targetBranch,
    [string]$primaryReleaseTag,
    [string]$newVersionTagPrefix, 
    [string]$newVersionTag,
    [string]$boardColumnField,
    [hashtable]$boardColumnMapping,
    [string[]]$repositories
)

. "$PSScriptRoot\Utility-Functions.ps1"

# Encode PAT for Basic Auth
$headers = @{
    Authorization = ("Basic {0}" -f [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$pat")))
}

# Get distinct Ticket IDs using the new utility function
$distinctTicketIds = Get-LinkedTicketIdsFromRepos -organization $organization -project $project -repositories $repositories -targetBranch $targetBranch -headers $headers

Write-Host "========================================="
Write-Host "Found $($distinctTicketIds.Count) Linked Ticket IDs (Distinct across repositories):"
# $distinctTicketIds

Write-Host "========================================="
Write-Host "Checking $newVersionTagPrefix tags on each ticket..."

$taggedTicketIds = @()  # Array to store tagged ticket IDs

foreach ($ticketId in $distinctTicketIds) {
    $canAddReleaseTag = Has-ReleaseTag -organization $organization -project $project -ticketId $ticketId -headers $headers -primaryReleaseTag $primaryReleaseTag -tagPrefix $newVersionTagPrefix

    if ($canAddReleaseTag) {
        Write-Host "✅ Ticket $ticketId has $primaryReleaseTag but no $newVersionTagPrefix tag."
        Add-ReleaseTag -organization $organization -project $project -ticketId $ticketId -headers $headers -newVersionTag $newVersionTag > $null
        $taggedTicketIds += $ticketId  # Add ticket ID to the array
        if($boardColumnMapping.Count -gt 0){
            Write-Host "Moving tickets across the board"
            Update-KanbanColumn -organization $organization -project $project -ticketId $ticketId -headers $headers -columnMapping $boardColumnMapping > $null
        }
   }
}

Write-Host "✅ Tagged & Moved $($taggedTicketIds.Count) tickets successfully"

# Save tagged ticket IDs to a file
$outputFile = "Release-Tagged-Tickets-$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
$taggedTicketIds | Out-File -FilePath $outputFile -Encoding UTF8
Write-Host "📄 Tagged ticket IDs saved to: $outputFile"