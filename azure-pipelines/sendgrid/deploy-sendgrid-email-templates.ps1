param (
    [string]$SOURCE_API_KEY,
    [string]$SOURCE_TEMPLATE_GENERATION = "legacy",
    [string]$TARGET_API_KEY,
    [string]$TARGET_TEMPLATE_GENERATION = "dynamic"
)

function Get-ExistingTemplates {
    param (
        [string]$apiKey,
        [string]$generation = "legacy"
    )

    $PARAMETERS = @{
        page_size   = 200
        generations = $generation
    }
    $HEADERS = @{'Authorization' = "Bearer ${apiKey}" }
    $templates = Invoke-WebRequest -Uri 'https://api.sendgrid.com/v3/templates' `
        -Method 'GET' `
        -Headers $HEADERS `
        -Body $PARAMETERS
    
    $decoded = ConvertFrom-Json -InputObject  $templates
    return $decoded
}

function IsAny {
    param (
        $items,
        [string]$searchTerm
    )

    $result = $items | Where-Object { $_.name -eq $searchTerm }
    $isAny = $null -ne $result
    return $isAny
}

function FindByName {
    param (
        $items,
        [string]$searchTerm
    )

    $result = $items | Where-Object { $_.name -eq $searchTerm }
    return $result
}

function  HasChanged {
    param (
        $item1,
        $item2
    )
    $date1 = [DateTime]$item1.updated_at
    $date2 = [DateTime]$item2.updated_at

    $changed = [Boolean]($date1 -gt $date2)
    return $changed
}

function Set-NewTemplate {
    param (
        [string]$name,
        [string]$sourceTemplateId,
        [string]$sourceApiKey,
        [string]$targetApiKey,
        [string]$generation = "dynamic"
    )

    $PARAMETERS = @{
        name       = $name
        generation = $generation
    }
    $HEADERS = @{
        'Authorization' = "Bearer ${targetApiKey}"
        'Content-Type'  = "application/json"
    }
    $response = Invoke-WebRequest -Uri 'https://api.sendgrid.com/v3/templates' `
        -Method 'POST' `
        -Headers $HEADERS `
        -Body (ConvertTo-Json $PARAMETERS)
    
    $decoded = ConvertFrom-Json -InputObject  $response
    $newTemplateId = $decoded.id

    $sourceTemplate = Get-ActiveTemplate -id $sourceTemplateId -apiKey $sourceApiKey

    $PARAMETERS2 = @{
        name         = $name
        generation   = $generation
        html_content = $sourceTemplate.html_content
        subject      = $sourceTemplate.subject
    }
    Invoke-WebRequest -Uri "https://api.sendgrid.com/v3/templates/${newTemplateId}/versions" `
        -Method 'POST' `
        -Headers $HEADERS `
        -Body (ConvertTo-Json $PARAMETERS2)
}

function Set-UpdateTemplate {
    param (
        [string]$name,
        [string]$sourceTemplateId,
        [string]$sourceApiKey,
        [string]$targetTemplateId,
        [string]$targetApiKey,
        [string]$targetTemplateVersion
    )

    $HEADERS = @{
        'Authorization' = "Bearer ${targetApiKey}"
        'Content-Type'  = "application/json"
    }

    $sourceTemplate = Get-ActiveTemplate -id $sourceTemplateId -apiKey $sourceApiKey
    
    $PARAMETERS2 = @{
        name         = $name
        html_content = $sourceTemplate.html_content
        subject      = $sourceTemplate.subject
    }
    Invoke-WebRequest -Uri "https://api.sendgrid.com/v3/templates/${targetTemplateId}/versions/${targetTemplateVersion}" `
        -Method 'PATCH' `
        -Headers $HEADERS `
        -Body (ConvertTo-Json $PARAMETERS2)
}

function Get-ActiveTemplate {
    param (
        [string]$id,
        [string]$apiKey
    )

    $HEADERS = @{
        'Authorization' = "Bearer ${apiKey}"
    }

    $response = Invoke-WebRequest -Uri "https://api.sendgrid.com/v3/templates/${id}" `
        -Method 'GET' `
        -Headers $HEADERS

    $decoded = ConvertFrom-Json -InputObject $response
    $activeTemplate = $decoded.versions | Where-Object { $_.active -eq 1 }
    return ($activeTemplate | Select-Object html_content, subject)
}

$sourceTemplates = Get-ExistingTemplates -apiKey $SOURCE_API_KEY -generation $SOURCE_TEMPLATE_GENERATION
$targetTemplates = Get-ExistingTemplates -apiKey $TARGET_API_KEY -generation $TARGET_TEMPLATE_GENERATION

$sourceTemplateItems = New-Object System.Collections.ArrayList
$targetTemplatesItems = New-Object System.Collections.ArrayList

foreach ($template in $sourceTemplates.result) {
    $activeVersion = ($template.versions | Where-Object { $_.active -eq 1 }) | Select-Object id, updated_at 
    $item = @{
        id         = $template.id
        name       = $template.name
        updated_at = $activeVersion.updated_at
        version_id = $activeVersion.Id
    }
    $sourceTemplateItems.Add($item)
}

foreach ($template in $targetTemplates.result) {
    $activeVersion = ($template.versions | Where-Object { $_.active -eq 1 }) | Select-Object id, updated_at 
    $item = @{
        id         = $template.id
        name       = $template.name
        updated_at = $activeVersion.updated_at
        version_id = $activeVersion.Id
    }
    $targetTemplatesItems.Add($item)
}

foreach ($sourceTemplate in $sourceTemplateItems) {
    $isAny = [bool](IsAny -items $targetTemplatesItems -searchTerm $sourceTemplate.name)
    $targetTemplate = FindByName -items $targetTemplatesItems -searchTerm $sourceTemplate.name
    $changed = $isAny -and (HasChanged -item1 $sourceTemplate -item2 $targetTemplate)
    
    if ($isAny -eq $false) {
        Write-Output "Source Template: $($sourceTemplate.name) - Not found -> CREATING"
        Set-NewTemplate -name $sourceTemplate.name `
            -sourceTemplateId $sourceTemplate.id `
            -sourceApiKey $SOURCE_API_KEY `
            -targetApiKey $TARGET_API_KEY `
            -generation $TARGET_TEMPLATE_GENERATION
    }
    elseif ($changed -eq $true) {
        Write-Output $sourceTemplate.version_id
        Write-Output "Source Template: $($sourceTemplate.name) - Exist & Has changes -> UPDATING"
        Set-UpdateTemplate -name $sourceTemplate.name `
            -sourceTemplateId $sourceTemplate.id `
            -sourceApiKey $SOURCE_API_KEY `
            -targetApiKey $TARGET_API_KEY `
            -targetTemplateId $targetTemplate.id `
            -targetTemplateVersion $targetTemplate.version_id
    }
    else {
        
        Write-Output "Source Template: $($sourceTemplate.name) - Exist & No changes -> SKIP"
    }
    
    # Write-Host  $isAny $changed
    # Write-Host $isAny
    # Write-Host ($template | Format-Table | Out-String)
}
