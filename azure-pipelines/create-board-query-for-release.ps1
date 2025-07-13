param(
    [string]$organization,
    [string]$project,
    [string]$pat,
    [string]$folderPath,
    [string]$targetFolderName,
    [string]$tag,
    [array]$queriesToCreate
)

$base64 = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$pat"))
$headers = @{ Authorization = "Basic $base64" }
$apiVersion = "7.1"
$fullFolderPath = "$folderPath/$targetFolderName"

function Get-Folder {
    param($path)
    $url = "https://dev.azure.com/$organization/$project/_apis/wit/queries/$( [uri]::EscapeDataString($path) )`?api-version=$apiVersion&`$depth=1"
    try { return Invoke-RestMethod -Uri $url -Headers $headers -Method Get } catch { return $null }
}

function Create-Folder {
    param($parentPath, $name)
    $url = "https://dev.azure.com/$organization/$project/_apis/wit/queries/$( [uri]::EscapeDataString($parentPath) )?api-version=$apiVersion"
    $body = @{ name = $name; isFolder = $true } | ConvertTo-Json
    Invoke-RestMethod -Uri $url -Headers $headers -Method Post -Body $body -ContentType "application/json" > $null
}

function Upsert-Query {
    param(
        [string]$parentPath,
        [string]$queryName,
        [string]$tag,
        [string]$mode
    )

    $queryPath = "$parentPath/$queryName"
    
    $getUrl = "https://dev.azure.com/$organization/$project/_apis/wit/queries/$($queryPath)?api-version=$apiVersion"
    $createUrl = "https://dev.azure.com/$organization/$project/_apis/wit/queries/$([uri]::EscapeDataString($parentPath))?api-version=$apiVersion"
    $wiql = "Select [System.Id], [System.Title] From WorkItems Where [System.Tags] Contains '$tag'"

    try {
        $existing = Invoke-RestMethod -Uri $getUrl -Headers $headers -Method Get
        $queryId = $existing.id
        $queryWebUrl = $existing.url

        # Now fetch WIQL explicitly
        $wiqlUrl = "https://dev.azure.com/$organization/$project/_apis/wit/queries/$($queryId)?api-version=$apiVersion&`$expand=wiql"
        $queryDetails = Invoke-RestMethod -Uri $wiqlUrl -Headers $headers -Method Get
        $existingWiql = $queryDetails.wiql

        # Decide how to update
         if ($mode -eq "Merge") {
            if ($existingWiql -notmatch [regex]::Escape($tag)) {
                $newWiql = "$existingWiql OR [System.Tags] Contains '$tag'"
            } else {
                $newWiql = $existingWiql
            }
        } else {
            $newWiql = $wiql
        }

        # Only patch if changed
        if ($newWiql -ne $existingWiql) {
            Write-Host "🔄 Updating query: $queryName"
            $patchBody = @{ wiql = $newWiql } | ConvertTo-Json
            $patchUrl = "https://dev.azure.com/$organization/$project/_apis/wit/queries/$($queryId)?api-version=$apiVersion"
            Invoke-RestMethod -Uri $patchUrl -Headers $headers -Method Patch -Body $patchBody -ContentType "application/json" > $null
        } else {
            Write-Host "✅ Query $queryName already includes tag '$tag'"
        }

        return "https://dev.azure.com/$organization/$project/_queries/query/$($queryId)"
    }
    catch {
        Write-Host "🆕 Creating new query: $queryName"
        $body = @{ name = $queryName; wiql = $wiql } | ConvertTo-Json
        $response = Invoke-RestMethod -Uri $createUrl -Headers $headers -Method Post -Body $body -ContentType "application/json"

        return "https://dev.azure.com/$organization/$project/_queries/query/$($response.id)"
    }
}

# STEP 1: Ensure folder exists
if (-not (Get-Folder -path $fullFolderPath)) {
    Write-Host "📁 Creating folder: $fullFolderPath"
    Create-Folder -parentPath $folderPath -name $targetFolderName
} else {
    Write-Host "✔ Folder exists: $fullFolderPath"
}

$queryLinks = @{}

# STEP 2: Ensure queries exist
foreach ($query in $queriesToCreate) {
    $url = Upsert-Query -parentPath $fullFolderPath -queryName $query.Name -tag $tag -mode $query.Mode
    $queryLinks[$query.Name] = $url
}

Write-Host "`n🔗 Final Query URLs:"
$queryLinks.GetEnumerator() | ForEach-Object {
    Write-Host "$($_.Key): $($_.Value)"
}