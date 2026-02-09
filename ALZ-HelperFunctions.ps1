<#
.SYNOPSIS
    Helper functions for Azure Landing Zone management.

.DESCRIPTION
    This script provides utility functions for:
    - Viewing the current Management Group hierarchy
    - Checking policy compliance
    - Listing subscriptions and their assignments
    - Cleanup operations

.NOTES
    Version: 1.0
    Requires: Az.Accounts, Az.Resources modules
#>

#region ==================== PREREQUISITE CHECK ====================

function Test-Prerequisites {
    Write-Host "Checking prerequisites..." -ForegroundColor Cyan
    
    # Check Az modules
    $requiredModules = @("Az.Accounts", "Az.Resources")
    $missingModules = @()
    
    foreach ($module in $requiredModules) {
        if (-not (Get-Module -ListAvailable -Name $module)) {
            $missingModules += $module
        }
    }
    
    if ($missingModules.Count -gt 0) {
        Write-Host "Missing required modules: $($missingModules -join ', ')" -ForegroundColor Red
        Write-Host "Install them using: Install-Module -Name <ModuleName> -Scope CurrentUser" -ForegroundColor Yellow
        return $false
    }
    
    # Check Azure connection
    $context = Get-AzContext
    if (-not $context) {
        Write-Host "Not connected to Azure. Run 'Connect-AzAccount' first." -ForegroundColor Red
        return $false
    }
    
    Write-Host "Prerequisites check passed." -ForegroundColor Green
    Write-Host "Connected as: $($context.Account.Id)" -ForegroundColor Gray
    Write-Host "Tenant: $($context.Tenant.Id)" -ForegroundColor Gray
    return $true
}

#endregion

#region ==================== VIEWING FUNCTIONS ====================

function Show-ManagementGroupHierarchy {
    <#
    .SYNOPSIS
        Displays the Management Group hierarchy in a tree format.
    
    .PARAMETER RootGroupName
        Optional. The name of the root management group to start from.
    #>
    param(
        [string]$RootGroupName = ""
    )
    
    Write-Host "`n╔══════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║              MANAGEMENT GROUP HIERARCHY                          ║" -ForegroundColor Cyan
    Write-Host "╚══════════════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan
    
    function Get-MGChildren {
        param(
            [string]$ParentId,
            [int]$Level = 0
        )
        
        $indent = "  " * $Level
        $children = Get-AzManagementGroup | Where-Object { 
            $_.ParentId -eq $ParentId -or 
            $_.ParentDisplayName -eq $ParentId -or
            $_.ParentName -eq $ParentId
        }
        
        foreach ($child in $children) {
            $icon = if ($Level -eq 0) { "📁" } else { "├── 📂" }
            Write-Host "$indent$icon $($child.DisplayName) [$($child.Name)]" -ForegroundColor White
            
            # Get subscriptions under this MG
            try {
                $subs = Get-AzManagementGroupSubscription -GroupName $child.Name -ErrorAction SilentlyContinue
                foreach ($sub in $subs) {
                    Write-Host "$indent    └── 🔑 $($sub.DisplayName)" -ForegroundColor Yellow
                }
            }
            catch {}
            
            Get-MGChildren -ParentId $child.Id -Level ($Level + 1)
        }
    }
    
    # Get tenant root
    $tenantRoot = Get-AzManagementGroup | Where-Object { $_.ParentId -eq $null }
    
    if ($RootGroupName) {
        $startMG = Get-AzManagementGroup -GroupName $RootGroupName -ErrorAction SilentlyContinue
        if ($startMG) {
            Write-Host "📁 $($startMG.DisplayName) [$($startMG.Name)]" -ForegroundColor Cyan
            Get-MGChildren -ParentId $startMG.Id -Level 1
        }
        else {
            Write-Host "Management Group '$RootGroupName' not found." -ForegroundColor Red
        }
    }
    else {
        Write-Host "📁 Tenant Root Group" -ForegroundColor Cyan
        Get-MGChildren -ParentId $tenantRoot.Id -Level 1
    }
    
    Write-Host ""
}

function Show-PolicyAssignments {
    <#
    .SYNOPSIS
        Lists all policy assignments at Management Group scope.
    
    .PARAMETER ManagementGroupName
        The name of the management group to check.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ManagementGroupName
    )
    
    Write-Host "`n╔══════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║              POLICY ASSIGNMENTS                                  ║" -ForegroundColor Cyan
    Write-Host "╚══════════════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan
    
    $scope = "/providers/Microsoft.Management/managementGroups/$ManagementGroupName"
    
    try {
        $assignments = Get-AzPolicyAssignment -Scope $scope -ErrorAction Stop
        
        if ($assignments.Count -eq 0) {
            Write-Host "No policy assignments found at scope: $ManagementGroupName" -ForegroundColor Yellow
            return
        }
        
        Write-Host "Management Group: $ManagementGroupName" -ForegroundColor White
        Write-Host "Total Assignments: $($assignments.Count)`n" -ForegroundColor Gray
        
        foreach ($assignment in $assignments) {
            Write-Host "  📋 $($assignment.Properties.DisplayName)" -ForegroundColor Green
            Write-Host "     Name: $($assignment.Name)" -ForegroundColor Gray
            Write-Host "     Policy: $($assignment.Properties.PolicyDefinitionId.Split('/')[-1])" -ForegroundColor Gray
            Write-Host ""
        }
    }
    catch {
        Write-Host "Error retrieving policy assignments: $_" -ForegroundColor Red
    }
}

function Show-PolicyCompliance {
    <#
    .SYNOPSIS
        Shows policy compliance summary for a Management Group.
    
    .PARAMETER ManagementGroupName
        The name of the management group to check.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ManagementGroupName
    )
    
    Write-Host "`n╔══════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║              POLICY COMPLIANCE SUMMARY                           ║" -ForegroundColor Cyan
    Write-Host "╚══════════════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan
    
    $scope = "/providers/Microsoft.Management/managementGroups/$ManagementGroupName"
    
    try {
        $complianceStates = Get-AzPolicyState -ManagementGroupName $ManagementGroupName -Filter "ComplianceState eq 'NonCompliant'" -Top 100 -ErrorAction Stop
        
        if ($complianceStates.Count -eq 0) {
            Write-Host "✅ All resources are compliant!" -ForegroundColor Green
            return
        }
        
        Write-Host "⚠️  Non-Compliant Resources Found: $($complianceStates.Count)`n" -ForegroundColor Yellow
        
        # Group by policy
        $grouped = $complianceStates | Group-Object -Property PolicyDefinitionName
        
        foreach ($group in $grouped) {
            Write-Host "  Policy: $($group.Name)" -ForegroundColor Red
            Write-Host "  Non-Compliant Count: $($group.Count)" -ForegroundColor Gray
            Write-Host ""
        }
    }
    catch {
        Write-Host "Error retrieving compliance data: $_" -ForegroundColor Red
        Write-Host "Note: Compliance data may take up to 24 hours to populate after policy assignment." -ForegroundColor Yellow
    }
}

function Show-Subscriptions {
    <#
    .SYNOPSIS
        Lists all subscriptions and their Management Group assignments.
    #>
    
    Write-Host "`n╔══════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║              SUBSCRIPTION LIST                                   ║" -ForegroundColor Cyan
    Write-Host "╚══════════════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan
    
    $subscriptions = Get-AzSubscription
    
    Write-Host "Found $($subscriptions.Count) subscriptions:`n" -ForegroundColor White
    
    foreach ($sub in $subscriptions) {
        $state = if ($sub.State -eq "Enabled") { "✅" } else { "⚠️" }
        Write-Host "  $state $($sub.Name)" -ForegroundColor White
        Write-Host "     ID: $($sub.Id)" -ForegroundColor Gray
        Write-Host "     State: $($sub.State)" -ForegroundColor Gray
        Write-Host ""
    }
}

function Show-EAEnrollmentAccount {
    <#
    .SYNOPSIS
        Shows EA Enrollment Account information for subscription creation.
    .DESCRIPTION
        Retrieves and displays the EA enrollment account scope needed for 
        automated subscription creation in the deployment script.
    #>
    
    Write-Host "`n╔══════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║         EA ENROLLMENT ACCOUNT INFORMATION                        ║" -ForegroundColor Cyan
    Write-Host "╚══════════════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan
    
    try {
        Write-Host "Querying EA Enrollment Accounts..." -ForegroundColor Gray
        $enrollmentAccounts = Get-AzEnrollmentAccount -ErrorAction Stop
        
        if ($enrollmentAccounts.Count -eq 0) {
            Write-Host "No EA Enrollment Accounts found." -ForegroundColor Yellow
            Write-Host "`nPossible reasons:" -ForegroundColor Gray
            Write-Host "  - You don't have EA enrollment account owner permissions" -ForegroundColor Gray
            Write-Host "  - Your organization doesn't use Enterprise Agreement" -ForegroundColor Gray
            Write-Host "  - Try running with a different account that has EA permissions" -ForegroundColor Gray
            return
        }
        
        Write-Host "Found $($enrollmentAccounts.Count) EA Enrollment Account(s):`n" -ForegroundColor Green
        
        foreach ($account in $enrollmentAccounts) {
            $billingScope = "/providers/Microsoft.Billing/billingAccounts/$($account.PrincipalName -replace '@.*', '')/enrollmentAccounts/$($account.ObjectId)"
            
            Write-Host "  📋 Principal: $($account.PrincipalName)" -ForegroundColor White
            Write-Host "     Object ID: $($account.ObjectId)" -ForegroundColor Gray
            Write-Host ""
            Write-Host "     🔑 Billing Scope (copy this to your config):" -ForegroundColor Yellow
            Write-Host "     $billingScope" -ForegroundColor Cyan
            Write-Host ""
            Write-Host "  ─────────────────────────────────────────────────────" -ForegroundColor DarkGray
        }
        
        Write-Host "`n📝 To enable subscription creation, update Deploy-AzureLandingZone.ps1:" -ForegroundColor White
        Write-Host @"

    Billing = @{
        CreateSubscriptions = `$true
        EnrollmentAccountScope = "<paste the billing scope from above>"
        WorkloadType = "Production"
    }

"@ -ForegroundColor Gray
        
    }
    catch {
        Write-Host "Error retrieving EA Enrollment Accounts: $_" -ForegroundColor Red
        Write-Host "`nAlternative method - try this command:" -ForegroundColor Yellow
        Write-Host "  az billing enrollment-account list" -ForegroundColor Cyan
    }
}

#endregion

#region ==================== CLEANUP FUNCTIONS ====================

function Remove-PolicyAssignments {
    <#
    .SYNOPSIS
        Removes policy assignments directly assigned to a Management Group (not inherited).
    
    .PARAMETER ManagementGroupName
        The name of the management group.
    
    .PARAMETER WhatIf
        Shows what would be removed without actually removing.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ManagementGroupName,
        
        [switch]$WhatIf
    )
    
    $scope = "/providers/Microsoft.Management/managementGroups/$ManagementGroupName"
    
    # Only get assignments directly at this scope (not inherited)
    $assignments = Get-AzPolicyAssignment -Scope $scope -ErrorAction SilentlyContinue | Where-Object {
        $_.Properties.Scope -eq $scope
    }
    
    if (-not $assignments -or $assignments.Count -eq 0) {
        Write-Host "  No direct policy assignments at this scope." -ForegroundColor Gray
        return
    }
    
    Write-Host "  Found $($assignments.Count) direct policy assignments." -ForegroundColor White
    
    foreach ($assignment in $assignments) {
        if ($WhatIf) {
            Write-Host "  [WhatIf] Would remove: $($assignment.Properties.DisplayName)" -ForegroundColor Yellow
        }
        else {
            Write-Host "  Removing: $($assignment.Properties.DisplayName)..." -ForegroundColor Cyan
            try {
                Remove-AzPolicyAssignment -Name $assignment.Name -Scope $scope -ErrorAction Stop
                Write-Host "    Removed." -ForegroundColor Green
            }
            catch {
                Write-Host "    Failed: $_" -ForegroundColor Red
            }
        }
    }
}

function Remove-ManagementGroupHierarchy {
    <#
    .SYNOPSIS
        Removes a Management Group and all its children.
        WARNING: This is destructive! Use with caution.
    
    .PARAMETER RootGroupName
        The name of the root management group to remove.
    
    .PARAMETER WhatIf
        Shows what would be removed without actually removing.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootGroupName,
        
        [switch]$WhatIf
    )
    
    Write-Host "`n⚠️  WARNING: This will remove the Management Group and all its children!" -ForegroundColor Red
    Write-Host "📌 NOTE: Subscriptions will be MOVED to tenant root (NOT deleted)." -ForegroundColor Green
    Write-Host "📌 NOTE: Resources within subscriptions are NOT affected." -ForegroundColor Green
    
    if (-not $WhatIf) {
        $confirm = Read-Host "Type 'DELETE' to confirm"
        if ($confirm -ne "DELETE") {
            Write-Host "Cancelled." -ForegroundColor Yellow
            return
        }
    }
    
    # Get the tenant root MG for moving subscriptions (subscriptions are MOVED, never deleted)
    $tenantRootMG = (Get-AzManagementGroup | Where-Object { $_.ParentId -eq $null })[0]
    
    function Remove-MGRecursive {
        param(
            [string]$GroupName
        )
        
        Write-Host "`nProcessing Management Group: $GroupName" -ForegroundColor Cyan
        
        # Get MG with expanded children
        $mg = Get-AzManagementGroup -GroupName $GroupName -Expand -ErrorAction SilentlyContinue
        
        if (-not $mg) {
            Write-Host "  Management Group not found: $GroupName" -ForegroundColor Yellow
            return
        }
        
        # Process children first (subscriptions and child MGs)
        if ($mg.Children) {
            foreach ($child in $mg.Children) {
                if ($child.Type -eq "/subscriptions") {
                    # MOVE subscription to tenant root (subscriptions are NEVER deleted)
                    $subId = $child.Name
                    if ($WhatIf) {
                        Write-Host "  [WhatIf] Would MOVE subscription '$($child.DisplayName)' to tenant root (not delete)" -ForegroundColor Yellow
                    }
                    else {
                        Write-Host "  MOVING subscription '$($child.DisplayName)' to tenant root (not deleting)..." -ForegroundColor Cyan
                        try {
                            New-AzManagementGroupSubscription -GroupName $tenantRootMG.Name -SubscriptionId $subId -ErrorAction Stop
                            Write-Host "    Moved successfully. Subscription preserved." -ForegroundColor Green
                        }
                        catch {
                            Write-Host "    Failed to move: $_" -ForegroundColor Red
                        }
                    }
                }
                elseif ($child.Type -eq "/providers/Microsoft.Management/managementGroups") {
                    # Recursively remove child MG
                    Remove-MGRecursive -GroupName $child.Name
                }
            }
        }
        
        # Remove policy assignments at this MG scope (direct only)
        Write-Host "  Removing policy assignments..." -ForegroundColor Cyan
        Remove-PolicyAssignments -ManagementGroupName $GroupName -WhatIf:$WhatIf
        
        # Remove role assignments at this scope (optional - uncomment if needed)
        # $scope = "/providers/Microsoft.Management/managementGroups/$GroupName"
        # $roleAssignments = Get-AzRoleAssignment -Scope $scope | Where-Object { $_.Scope -eq $scope }
        # foreach ($ra in $roleAssignments) {
        #     Remove-AzRoleAssignment -ObjectId $ra.ObjectId -Scope $scope -RoleDefinitionName $ra.RoleDefinitionName
        # }
        
        # Now remove the MG itself
        if ($WhatIf) {
            Write-Host "  [WhatIf] Would remove MG: $GroupName" -ForegroundColor Yellow
        }
        else {
            Write-Host "  Removing Management Group: $GroupName..." -ForegroundColor Cyan
            try {
                # Small delay to ensure Azure has processed child removals
                Start-Sleep -Seconds 2
                Remove-AzManagementGroup -GroupName $GroupName -ErrorAction Stop
                Write-Host "  ✅ Removed: $GroupName" -ForegroundColor Green
            }
            catch {
                Write-Host "  ❌ Failed to remove $GroupName : $_" -ForegroundColor Red
            }
        }
    }
    
    Remove-MGRecursive -GroupName $RootGroupName
    
    if (-not $WhatIf) {
        Write-Host "`n✅ Cleanup completed." -ForegroundColor Green
        Write-Host "📌 All subscriptions have been preserved and moved to the tenant root." -ForegroundColor Green
    }
}

#endregion

#region ==================== INTERACTIVE MENU ====================

function Show-Menu {
    Clear-Host
    Write-Host "╔══════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║         AZURE LANDING ZONE MANAGEMENT UTILITIES                  ║" -ForegroundColor Cyan
    Write-Host "╚══════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  1. Check Prerequisites" -ForegroundColor White
    Write-Host "  2. Show Management Group Hierarchy" -ForegroundColor White
    Write-Host "  3. Show Policy Assignments" -ForegroundColor White
    Write-Host "  4. Show Policy Compliance" -ForegroundColor White
    Write-Host "  5. List Subscriptions" -ForegroundColor White
    Write-Host "  6. Show EA Enrollment Account (for subscription creation)" -ForegroundColor White
    Write-Host ""
    Write-Host "  7. Run Deployment Script" -ForegroundColor Green
    Write-Host ""
    Write-Host "  8. Remove Policy Assignments" -ForegroundColor Yellow
    Write-Host "  9. Remove Management Group Hierarchy" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Q. Quit" -ForegroundColor Gray
    Write-Host ""
}

function Start-InteractiveMenu {
    do {
        Show-Menu
        $selection = Read-Host "Select an option"
        
        switch ($selection) {
            '1' {
                Test-Prerequisites
                Read-Host "`nPress Enter to continue"
            }
            '2' {
                $mgName = Read-Host "Enter Management Group name (or press Enter for all)"
                if ($mgName) {
                    Show-ManagementGroupHierarchy -RootGroupName $mgName
                }
                else {
                    Show-ManagementGroupHierarchy
                }
                Read-Host "`nPress Enter to continue"
            }
            '3' {
                $mgName = Read-Host "Enter Management Group name"
                if ($mgName) {
                    Show-PolicyAssignments -ManagementGroupName $mgName
                }
                Read-Host "`nPress Enter to continue"
            }
            '4' {
                $mgName = Read-Host "Enter Management Group name"
                if ($mgName) {
                    Show-PolicyCompliance -ManagementGroupName $mgName
                }
                Read-Host "`nPress Enter to continue"
            }
            '5' {
                Show-Subscriptions
                Read-Host "`nPress Enter to continue"
            }
            '6' {
                Show-EAEnrollmentAccount
                Read-Host "`nPress Enter to continue"
            }
            '7' {
                Write-Host "`n╔══════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
                Write-Host "║              DEPLOYMENT MODE SELECTION                           ║" -ForegroundColor Cyan
                Write-Host "╚══════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
                Write-Host ""
                Write-Host "  1. Dry Run Mode (Preview only - no changes)" -ForegroundColor Yellow
                Write-Host "  2. Live Mode (Apply changes to Azure)" -ForegroundColor Red
                Write-Host "  Q. Cancel" -ForegroundColor Gray
                Write-Host ""
                $modeSelection = Read-Host "Select deployment mode"
                
                $dryRunValue = $null
                switch ($modeSelection) {
                    '1' { $dryRunValue = $true }
                    '2' { $dryRunValue = $false }
                    default {
                        Write-Host "Cancelled." -ForegroundColor Yellow
                        Read-Host "`nPress Enter to continue"
                        continue
                    }
                }
                
                Write-Host "`nRunning deployment script..." -ForegroundColor Cyan
                Write-Host "─────────────────────────────────────────────────────────────────`n" -ForegroundColor DarkGray
                try {
                    & "$PSScriptRoot\Deploy-AzureLandingZone.ps1" -DryRun $dryRunValue
                }
                catch {
                    Write-Host "`nDeployment encountered an error: $_" -ForegroundColor Red
                }
                Write-Host "`n─────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray
                Write-Host "Deployment script finished." -ForegroundColor Cyan
                Read-Host "`nPress Enter to return to menu"
            }
            '8' {
                $mgName = Read-Host "Enter Management Group name"
                if ($mgName) {
                    Write-Host "`n  1. Preview only (WhatIf)" -ForegroundColor Yellow
                    Write-Host "  2. Actually remove" -ForegroundColor Red
                    Write-Host "  Q. Cancel" -ForegroundColor Gray
                    $removeMode = Read-Host "`nSelect mode"
                    
                    switch ($removeMode) {
                        '1' { Remove-PolicyAssignments -ManagementGroupName $mgName -WhatIf }
                        '2' { Remove-PolicyAssignments -ManagementGroupName $mgName }
                        default { Write-Host "Cancelled." -ForegroundColor Yellow }
                    }
                }
                Read-Host "`nPress Enter to continue"
            }
            '9' {
                $mgName = Read-Host "Enter root Management Group name to remove"
                if ($mgName) {
                    Write-Host "`n  1. Preview only (WhatIf)" -ForegroundColor Yellow
                    Write-Host "  2. Actually remove" -ForegroundColor Red
                    Write-Host "  Q. Cancel" -ForegroundColor Gray
                    $removeMode = Read-Host "`nSelect mode"
                    
                    switch ($removeMode) {
                        '1' { Remove-ManagementGroupHierarchy -RootGroupName $mgName -WhatIf }
                        '2' { Remove-ManagementGroupHierarchy -RootGroupName $mgName }
                        default { Write-Host "Cancelled." -ForegroundColor Yellow }
                    }
                }
                Read-Host "`nPress Enter to continue"
            }
        }
    } while ($selection -ne 'Q' -and $selection -ne 'q')
    
    Write-Host "`nGoodbye!" -ForegroundColor Green
}

#endregion

# Show usage info
Write-Host "`nAzure Landing Zone Helper Functions Loaded" -ForegroundColor Green
Write-Host "Available commands:" -ForegroundColor Cyan
Write-Host "  Start-InteractiveMenu          - Launch interactive menu" -ForegroundColor White
Write-Host "  Test-Prerequisites             - Check Azure connection and modules" -ForegroundColor White
Write-Host "  Show-ManagementGroupHierarchy  - Display MG tree" -ForegroundColor White
Write-Host "  Show-PolicyAssignments         - List policies at MG scope" -ForegroundColor White
Write-Host "  Show-PolicyCompliance          - Check compliance status" -ForegroundColor White
Write-Host "  Show-Subscriptions             - List all subscriptions" -ForegroundColor White
Write-Host "  Show-EAEnrollmentAccount       - Get EA billing scope for subscription creation" -ForegroundColor Yellow
Write-Host ""
Write-Host "Cleanup commands (use with caution):" -ForegroundColor Red
Write-Host "  Remove-PolicyAssignments       - Remove policies from a MG (use -WhatIf first)" -ForegroundColor Yellow
Write-Host "  Remove-ManagementGroupHierarchy - Remove MG and all children (use -WhatIf first)" -ForegroundColor Yellow
Write-Host ""
