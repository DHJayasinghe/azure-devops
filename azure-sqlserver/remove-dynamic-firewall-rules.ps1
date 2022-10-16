$ResourceNames = ("yourdbserver")
$ExcludeCriteria = 'exclude_rules_starts_with_name'

foreach ($ResourceName in $ResourceNames) {
    $Resource = Get-AzResource -Name $ResourceName  -ResourceType 'Microsoft.Sql/servers'
    $ResourceGroup = $Resource.ResourceGroupName
    
    Write-Host "Running script for Azure SQL Server: $($ResourceName)"

    try { 
        Write-Host "Removing resource lock..."
        $null = Remove-AzResourceLock -LockName "PreventDelete" `
            -ResourceName $ResourceName `
            -ResourceGroupName $ResourceGroup  `
            -ResourceType "Microsoft.Sql/servers" `
            -Force `
            -ErrorAction Stop
    }
    catch { 
        $message = $_.Exception.message
    
        if ($message.Contains("could not be found")) {
            Write-Output "Specified resource lock not found"
        }
        else {
            Write-Host "Failure: $($message)"
        }
    }

    $firewallRules = (Get-AzSqlServerFirewallRule -ServerName $ResourceName `
            -ResourceGroupName $ResourceGroup) `
    | Where-Object -FilterScript { $_.FirewallRuleName -ne 'AllowAllWindowsAzureIps' `
            -and ([string]::IsNullOrEmpty($ExcludeCriteria) -or $_.FirewallRuleName -notcontains $ExcludeCriteria) 
    } 

    Write-Host "Removing firewall rules..."
    foreach ($firewallRule in $firewallRules) {
        Remove-AzSqlServerFirewallRule `
            -FirewallRuleName $firewallRule.FirewallRuleName `
            -Force `
            -ServerName $ResourceName `
            -ResourceGroupName $ResourceGroup
    }

    Write-Host "Reseting resource lock..."
    New-AzResourceLock -LockLevel CanNotDelete `
        -LockName "PreventDelete" `
        -ResourceName $ResourceName `
        -ResourceType "Microsoft.Sql/servers" `
        -ResourceGroupName $ResourceGroup `
        -Force
}
