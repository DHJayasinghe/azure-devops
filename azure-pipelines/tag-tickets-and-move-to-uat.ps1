param (
    [string]$organization,
    [string]$project,
    [string]$pat,
    [string]$targetBranch,
    [string]$primaryReleaseTag,
    [string]$newVersionTag,
    [string]$boardColumnField,
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
Write-Host "Checking #Release- tags on each ticket..."

$taggedTicketIds = @()  # Array to store tagged ticket IDs

foreach ($ticketId in $distinctTicketIds) {
    $canAddReleaseTag = Has-ReleaseTag -organization $organization -project $project -ticketId $ticketId -headers $headers -primaryReleaseTag $primaryReleaseTag

    if ($canAddReleaseTag) {
        Write-Host "✅ Ticket $ticketId has $primaryReleaseTag but no #Release- tag."
        Add-ReleaseTag -organization $organization -project $project -ticketId $ticketId -headers $headers -newVersionTag $newVersionTag > $null
        $taggedTicketIds += $ticketId  # Add ticket ID to the array
        Update-KanbanColumn -organization $organization -project $project -ticketId $ticketId -headers $headers > $null
   }
}

Write-Host "✅ Tagged & Moved $($taggedTicketIds.Count) tickets successfully"

# Save tagged ticket IDs to a file
$outputFile = "tagged_tickets_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
$taggedTicketIds | Out-File -FilePath $outputFile -Encoding UTF8
Write-Host "📄 Tagged ticket IDs saved to: $outputFile"