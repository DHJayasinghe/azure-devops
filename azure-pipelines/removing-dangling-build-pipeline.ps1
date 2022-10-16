$organization = ""
$project = ""
$personalAccessToken = ""
$definitionId = "77"
$apiVersion = "6.0"

$token = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes(":$($personalAccessToken)"))
$header = @{authorization = "Basic $token" }

# References: https://docs.microsoft.com/en-us/rest/api/azure/devops/build/leases/delete?view=azure-devops-rest-6.0
# https://docs.microsoft.com/en-us/rest/api/azure/devops/build/definitions/delete?view=azure-devops-rest-6.0

# $url = "https://dev.azure.com/$organization/$project/_apis/build/definitions/$definitionId?api-version=3.2"
# Write-Host $url
# $buildDefinitions = Invoke-RestMethod -Uri $url -Method Get -ContentType "application/json" -Headers $header

function DeleteLease($definitionId) {
    $url = "https://dev.azure.com/$organization/$project/_apis/build/retention/leases?api-version=$apiVersion&definitionId=$definitionId"
    $leases = (Invoke-RestMethod -Method GET -Uri $url -ContentType "application/json" -Headers $header )

    foreach ($lease in $leases.value) {
        $leaseId = $lease.leaseId
        $url = "https://dev.azure.com/$organization/$project/_apis/build/retention/leases?ids=$($leaseId)&api-version=$apiVersion"
        $ignore = Invoke-RestMethod -Method DELETE -Uri $url -ContentType "application/json" -Headers $header
    }
}

function DeleteDefinition($definitionId) {
    $url = "https://dev.azure.com/$organization/$project/_apis/build/definitions/$definitionId?api-version=$apiVersion"
    Invoke-RestMethod -Method DELETE -Uri $url -ContentType "application/json" -Headers $header
}

DeleteLease $definitionId
# DeleteDefinition $definitionId
