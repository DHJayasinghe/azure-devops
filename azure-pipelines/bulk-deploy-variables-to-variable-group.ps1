$ORGANIZATION_ID = 'DEV_OPS_ORGANIZATION_ID'
$PROJECT_NAME = 'PROJECT_NAME'
$GROUP_ID = '18'

$job = Import-Csv -Path 'C:\Users\DhanukaJayasinghe\Downloads\convertcsv (1).csv' | ForEach-Object {\
    Write-Host $_.Name.replace(':', '.')
    $Key = $_.Name.replace(':', '.')
    $Value = $_.Value
    az pipelines variable-group variable create --group-id $GROUP_ID --name $Key --value $Value --organization $ORGANIZATION_ID --project $PROJECT_NAME
}