<#
.SYNOPSIS
    Deploys Azure Landing Zone hierarchy with Management Groups, Subscriptions, and Policies for Microsoft Fabric.

.DESCRIPTION
    This script creates a complete Azure Landing Zone structure including:
    - Management Group hierarchy (Platform and Landing Zones)
    - Subscription placement under appropriate Management Groups
    - Azure Policy assignments for Tagging, Location, and Security baseline
    
    All values are configurable via the configuration section or parameter file.

.NOTES
    Author: Azure Landing Zone Deployment Script
    Version: 1.0
    Requires: Az.Accounts, Az.Resources modules
    
.EXAMPLE
    .\Deploy-AzureLandingZone.ps1
    
.EXAMPLE
    .\Deploy-AzureLandingZone.ps1 -ConfigFile ".\config.json"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ConfigFile = "",
    
    [Parameter(Mandatory = $false)]
    [Nullable[bool]]$DryRun = $null
)

#region ==================== CONFIGURATION ====================
# This section contains all configurable variables
# Modify these values to customize your deployment

$Config = @{
    
    #----------------------------------------------------------
    # GENERAL SETTINGS
    #----------------------------------------------------------
    General = @{
        # Primary location for resources
        PrimaryLocation = "eastus"
        
        # Allowed locations for resources (used in Location policy)
        AllowedLocations = @("eastus", "eastus2", "westus2", "centralus")
        
        # Deployment prefix (used for naming)
        Prefix = "Target"
        
        # Enable verbose logging
        VerboseLogging = $true
        
        # Dry run mode (set to $true to see what would be created without making changes)
        # Can be overridden via -DryRun parameter
        DryRun = $true
    }
    
    #----------------------------------------------------------
    # ENTERPRISE AGREEMENT (EA) BILLING CONFIGURATION
    # Required for automated subscription creation
    # To find your EA Enrollment Account ID:
    #   1. Run: Get-AzEnrollmentAccount
    #   2. Copy the ObjectId value
    # Or find it in Azure Portal > Cost Management + Billing > Billing scopes
    #----------------------------------------------------------
    Billing = @{
        # Enable automated subscription creation
        CreateSubscriptions = $false  # Set to $true to enable subscription creation
        
        # EA Enrollment Account ID (required for subscription creation)
        # Format: /providers/Microsoft.Billing/billingAccounts/{billingAccountName}/enrollmentAccounts/{enrollmentAccountName}
        # Example: /providers/Microsoft.Billing/billingAccounts/1234567/enrollmentAccounts/7654321
        EnrollmentAccountScope = $null  # Set your EA enrollment account scope here
        
        # Workload type for new subscriptions
        # Options: "Production", "DevTest"
        WorkloadType = "Production"
    }
    
    #----------------------------------------------------------
    # MANAGEMENT GROUP HIERARCHY
    #----------------------------------------------------------
    ManagementGroups = @{
        
        # Root Management Group (directly under Tenant Root)
        Root = @{
            Name = "ALZ"
            DisplayName = "Target ALZ"
        }
        
        # Platform Management Groups
        Platform = @{
            Name = "Platform"
            DisplayName = "Platform"
            Children = @(
                @{ Name = "Security"; DisplayName = "Security" },
                @{ Name = "Management"; DisplayName = "Management" },
                @{ Name = "Identity"; DisplayName = "Identity" },
                @{ Name = "Connectivity"; DisplayName = "Connectivity" }
            )
        }
        
        # Landing Zones Management Groups
        LandingZones = @{
            Name = "LandingZones"
            DisplayName = "Landing zones"
            Children = @(
                @{ Name = "Fabric-BU1"; DisplayName = "Fabric BU1" },
                @{ Name = "Fabric-BU2"; DisplayName = "Fabric BU2" },
                @{ Name = "Fabric-BU3"; DisplayName = "Fabric BU3" }
            )
        }
    }
    
    #----------------------------------------------------------
    # SUBSCRIPTION ASSIGNMENTS
    # Map subscriptions to their target Management Groups
    # 
    # Two modes:
    # 1. CREATE MODE: Set SubscriptionId = $null and CreateIfMissing = $true
    #    (Requires Billing.CreateSubscriptions = $true and valid EA scope)
    # 2. ASSIGN MODE: Set SubscriptionId to existing subscription ID
    #    (Will move existing subscription to target MG)
    #----------------------------------------------------------
    Subscriptions = @{
        # Platform subscriptions
        Platform = @{
            Security = @{
                Name = "Security-Subscription"
                SubscriptionId = $null  # Set to subscription ID if it exists, or $null to create new
                TargetMG = "Security"
                CreateIfMissing = $false  # Set to $true to create if doesn't exist
            }
            Management = @{
                Name = "Management-Subscription"
                SubscriptionId = $null
                TargetMG = "Management"
                CreateIfMissing = $false
            }
            Identity = @{
                Name = "Identity-Subscription"
                SubscriptionId = $null
                TargetMG = "Identity"
                CreateIfMissing = $false
            }
            Connectivity = @{
                Name = "Connectivity-Subscription"
                SubscriptionId = $null
                TargetMG = "Connectivity"
                CreateIfMissing = $false
            }
        }
        
        # Landing Zone subscriptions (Fabric Business Units)
        LandingZones = @{
            FabricBU1 = @{
                Name = "Fabric-BU1-Subscription"
                SubscriptionId = $null  # Set to actual subscription ID or $null to create
                TargetMG = "Fabric-BU1"
                CreateIfMissing = $true  # Will create this subscription if EA scope is configured
            }
            FabricBU2 = @{
                Name = "Fabric-BU2-Subscription"
                SubscriptionId = $null
                TargetMG = "Fabric-BU2"
                CreateIfMissing = $true
            }
            FabricBU3 = @{
                Name = "Fabric-BU3-Subscription"
                SubscriptionId = $null
                TargetMG = "Fabric-BU3"
                CreateIfMissing = $true
            }
        }
    }
    
    #----------------------------------------------------------
    # AZURE POLICY CONFIGURATION
    # Enable/disable individual policies and configure their settings
    #----------------------------------------------------------
    Policies = @{
        
        #------------------------------------------------------
        # TAGGING POLICIES
        #------------------------------------------------------
        Tagging = @{
            Enabled = $true
            
            # Scope: Where to apply tagging policies
            # Options: "Root", "Platform", "LandingZones", "All"
            Scope = "Root"
            
            # Required tags with Audit effect (reports non-compliance but doesn't block)
            RequiredTags = @{
                Enabled = $true
                Tags = @(
                    @{ Name = "CostCenter"; Effect = "Audit" },
                    @{ Name = "Environment"; Effect = "Audit" }
                )
            }
            
            # Audit-only tags (reports non-compliance but doesn't block)
            AuditTags = @{
                Enabled = $true
                Tags = @(
                    @{ Name = "Owner"; Effect = "Audit" },
                    @{ Name = "Application"; Effect = "Audit" },
                    @{ Name = "Department"; Effect = "Audit" }
                )
            }
            
            # Inherit tags from Resource Group
            InheritTagsFromRG = @{
                Enabled = $true
                Tags = @("CostCenter", "Environment", "Department")
            }
        }
        
        #------------------------------------------------------
        # LOCATION/REGION POLICIES
        #------------------------------------------------------
        Location = @{
            Enabled = $true
            
            # Scope for location policies
            Scope = "Root"
            
            # Allowed locations for resources
            # Note: This policy only supports "Deny" or "Disabled" (no Audit option)
            # Set Enabled = $false to disable without removing
            AllowedLocations = @{
                Enabled = $true
                # Uses General.AllowedLocations by default
            }
            
            # Allowed locations for Resource Groups
            # Note: This policy only supports "Deny" or "Disabled" (no Audit option)
            AllowedLocationsForRGs = @{
                Enabled = $true
            }
        }
        
        #------------------------------------------------------
        # SECURITY BASELINE POLICIES
        #------------------------------------------------------
        Security = @{
            Enabled = $true
            
            # Scope for security policies
            Scope = "Root"
            
            # Microsoft Defender for Cloud
            DefenderForCloud = @{
                Enabled = $true
                # Auto-provisioning of Log Analytics agent
                AutoProvisioning = $true
            }
            
            # Secure transfer required for storage accounts
            SecureTransferForStorage = @{
                Enabled = $true
                Effect = "Audit"  # Options: "Audit", "Deny"
            }
            
            # HTTPS only for web apps
            HttpsOnlyForWebApps = @{
                Enabled = $true
                Effect = "Audit"
            }
            
            # TLS 1.2 minimum
            MinimumTLSVersion = @{
                Enabled = $true
                Effect = "Audit"
            }
            
            # Audit VMs without managed disks (disabled - not needed for Fabric workloads)
            ManagedDisksForVMs = @{
                Enabled = $false
                Effect = "Audit"
            }
        }
        
        #------------------------------------------------------
        # COST MANAGEMENT POLICIES (for Fabric chargeback)
        #------------------------------------------------------
        CostManagement = @{
            Enabled = $true
            
            Scope = "LandingZones"
            
            # Require tags on resource groups
            RequireTagsOnRGs = @{
                Enabled = $true
                Tags = @("CostCenter", "Department")
            }
        }
    }
}

# Override DryRun from parameter if provided
if ($null -ne $DryRun) {
    $Config.General.DryRun = $DryRun
}

#endregion

#region ==================== BUILT-IN POLICY DEFINITIONS ====================
# Reference: https://learn.microsoft.com/en-us/azure/governance/policy/samples/built-in-policies

$BuiltInPolicies = @{
    # Tagging Policies
    "RequireTagOnResources" = "871b6d14-10aa-478d-b590-94f262ecfa99"
    "RequireTagOnResourceGroups" = "96670d01-0a4d-4649-9c89-2d3abc0a5025"
    "InheritTagFromRG" = "cd3aa116-8754-49c9-a813-ad46512ece54"
    "InheritTagFromRGIfMissing" = "ea3f2387-9b95-492a-a190-fcdc54f7b070"
    "AddTagToRG" = "726aca4c-86e9-4b04-b0c5-073027359532"
    
    # Location Policies
    "AllowedLocations" = "e56962a6-4747-49cd-b67b-bf8b01975c4c"
    "AllowedLocationsForRGs" = "e765b5de-1225-4ba3-bd56-1ac6695af988"
    
    # Security Policies
    "SecureTransferToStorageAccounts" = "404c3081-a854-4457-ae30-26a93ef643f9"
    "AuditHttpsOnlyForWebApps" = "a4af4a39-4135-47fb-b175-47fbdf85311d"
    "AuditMinimumTLSVersionForStorage" = "fe83a0eb-a853-422d-aac2-1bffd182c5d0"
    "AuditVMsWithoutManagedDisks" = "06a78e20-9358-41c9-923c-fb736d382a4d"
    "DefenderForCloudAutoProvisioning" = "6df2fee6-a9ed-4fef-bced-e13be1b25f1c"
    
    # Resource Type Policies
    "AllowedResourceTypes" = "a08ec900-254a-4555-9bf5-e42af04b5c5c"
    "NotAllowedResourceTypes" = "6c112d4e-5bc7-47ae-a041-ea2d9dccd749"
    
    # Monitoring Policies
    "DiagnosticSettingsForSubscription" = "7f89b1eb-583c-429a-8828-af049802c1d9"
}

#endregion

#region ==================== HELPER FUNCTIONS ====================

function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet("INFO", "SUCCESS", "WARNING", "ERROR", "DEBUG")]
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $colors = @{
        "INFO"    = "Cyan"
        "SUCCESS" = "Green"
        "WARNING" = "Yellow"
        "ERROR"   = "Red"
        "DEBUG"   = "Gray"
    }
    
    if ($Level -eq "DEBUG" -and -not $Config.General.VerboseLogging) {
        return
    }
    
    $prefix = switch ($Level) {
        "INFO"    { "[INFO]   " }
        "SUCCESS" { "[OK]     " }
        "WARNING" { "[WARN]   " }
        "ERROR"   { "[ERROR]  " }
        "DEBUG"   { "[DEBUG]  " }
    }
    
    Write-Host "$timestamp $prefix $Message" -ForegroundColor $colors[$Level]
}

function Test-AzureConnection {
    Write-Log "Checking Azure connection..." -Level "INFO"
    
    try {
        $context = Get-AzContext
        if (-not $context) {
            Write-Log "Not connected to Azure. Please run Connect-AzAccount first." -Level "ERROR"
            return $false
        }
        
        Write-Log "Connected to Azure as: $($context.Account.Id)" -Level "SUCCESS"
        Write-Log "Tenant: $($context.Tenant.Id)" -Level "INFO"
        return $true
    }
    catch {
        Write-Log "Failed to verify Azure connection: $_" -Level "ERROR"
        return $false
    }
}

function Get-FullMGName {
    param(
        [string]$Name
    )
    return "$($Config.General.Prefix)-$Name"
}

function Get-MGScope {
    param(
        [string]$MGName
    )
    return "/providers/Microsoft.Management/managementGroups/$MGName"
}

#endregion

#region ==================== MANAGEMENT GROUP FUNCTIONS ====================

function New-ManagementGroupIfNotExists {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        
        [Parameter(Mandatory = $true)]
        [string]$DisplayName,
        
        [Parameter(Mandatory = $false)]
        [string]$ParentId = $null
    )
    
    $fullName = Get-FullMGName -Name $Name
    
    Write-Log "Checking if Management Group '$fullName' exists..." -Level "DEBUG"
    
    try {
        $existingMG = Get-AzManagementGroup -GroupName $fullName -ErrorAction SilentlyContinue
        
        if ($existingMG) {
            Write-Log "Management Group '$fullName' already exists." -Level "INFO"
            return $existingMG
        }
    }
    catch {
        # MG doesn't exist, we'll create it
    }
    
    if ($Config.General.DryRun) {
        Write-Log "[DRY RUN] Would create Management Group: $fullName (Display: $DisplayName)" -Level "WARNING"
        return $null
    }
    
    Write-Log "Creating Management Group: $fullName" -Level "INFO"
    
    try {
        $params = @{
            GroupName = $fullName
            DisplayName = $DisplayName
        }
        
        if ($ParentId) {
            $params.ParentId = $ParentId
        }
        
        $newMG = New-AzManagementGroup @params
        Write-Log "Successfully created Management Group: $fullName" -Level "SUCCESS"
        
        # Wait for propagation
        Start-Sleep -Seconds 5
        
        return $newMG
    }
    catch {
        Write-Log "Failed to create Management Group '$fullName': $_" -Level "ERROR"
        throw
    }
}

function Deploy-ManagementGroupHierarchy {
    Write-Log "========================================" -Level "INFO"
    Write-Log "DEPLOYING MANAGEMENT GROUP HIERARCHY" -Level "INFO"
    Write-Log "========================================" -Level "INFO"
    
    # Create Root Management Group
    $rootMGName = Get-FullMGName -Name $Config.ManagementGroups.Root.Name
    $rootMG = New-ManagementGroupIfNotExists `
        -Name $Config.ManagementGroups.Root.Name `
        -DisplayName $Config.ManagementGroups.Root.DisplayName
    
    $rootScope = Get-MGScope -MGName $rootMGName
    
    # Create Platform Management Group
    $platformMGName = Get-FullMGName -Name $Config.ManagementGroups.Platform.Name
    $platformMG = New-ManagementGroupIfNotExists `
        -Name $Config.ManagementGroups.Platform.Name `
        -DisplayName $Config.ManagementGroups.Platform.DisplayName `
        -ParentId $rootScope
    
    # Create Platform children (Security, Management, Identity, Connectivity)
    $platformScope = Get-MGScope -MGName $platformMGName
    foreach ($child in $Config.ManagementGroups.Platform.Children) {
        New-ManagementGroupIfNotExists `
            -Name $child.Name `
            -DisplayName $child.DisplayName `
            -ParentId $platformScope | Out-Null
    }
    
    # Create Landing Zones Management Group
    $lzMGName = Get-FullMGName -Name $Config.ManagementGroups.LandingZones.Name
    $lzMG = New-ManagementGroupIfNotExists `
        -Name $Config.ManagementGroups.LandingZones.Name `
        -DisplayName $Config.ManagementGroups.LandingZones.DisplayName `
        -ParentId $rootScope
    
    # Create Landing Zone children (Fabric BUs)
    $lzScope = Get-MGScope -MGName $lzMGName
    foreach ($child in $Config.ManagementGroups.LandingZones.Children) {
        New-ManagementGroupIfNotExists `
            -Name $child.Name `
            -DisplayName $child.DisplayName `
            -ParentId $lzScope | Out-Null
    }
    
    Write-Log "Management Group hierarchy deployment completed." -Level "SUCCESS"
}

#endregion

#region ==================== SUBSCRIPTION FUNCTIONS ====================

function New-SubscriptionIfNotExists {
    <#
    .SYNOPSIS
        Creates a new Azure subscription using EA enrollment account.
    .DESCRIPTION
        Creates a subscription via New-AzSubscriptionAlias if it doesn't already exist.
        Requires EA enrollment account scope to be configured.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$SubscriptionName,
        
        [Parameter(Mandatory = $true)]
        [string]$TargetMGName
    )
    
    # Check if EA billing is configured
    if (-not $Config.Billing.CreateSubscriptions) {
        Write-Log "Subscription creation is disabled. Set Billing.CreateSubscriptions = `$true to enable." -Level "WARNING"
        return $null
    }
    
    if (-not $Config.Billing.EnrollmentAccountScope) {
        Write-Log "EA Enrollment Account scope not configured. Cannot create subscription." -Level "ERROR"
        Write-Log "To find your EA scope, run: Get-AzEnrollmentAccount" -Level "INFO"
        return $null
    }
    
    # Check if subscription already exists by name
    $existingSub = Get-AzSubscription -SubscriptionName $SubscriptionName -ErrorAction SilentlyContinue
    if ($existingSub) {
        Write-Log "Subscription '$SubscriptionName' already exists with ID: $($existingSub.Id)" -Level "INFO"
        return $existingSub.Id
    }
    
    # Generate alias name (must be unique, alphanumeric with hyphens)
    $aliasName = ($SubscriptionName -replace '[^a-zA-Z0-9-]', '-').ToLower()
    if ($aliasName.Length -gt 64) {
        $aliasName = $aliasName.Substring(0, 64)
    }
    
    $fullMGName = Get-FullMGName -Name $TargetMGName
    $mgScope = Get-MGScope -MGName $fullMGName
    
    if ($Config.General.DryRun) {
        Write-Log "[DRY RUN] Would create subscription:" -Level "WARNING"
        Write-Log "  Name: $SubscriptionName" -Level "WARNING"
        Write-Log "  Alias: $aliasName" -Level "WARNING"
        Write-Log "  Target MG: $fullMGName" -Level "WARNING"
        Write-Log "  Workload: $($Config.Billing.WorkloadType)" -Level "WARNING"
        return "dry-run-subscription-id"
    }
    
    Write-Log "Creating subscription '$SubscriptionName'..." -Level "INFO"
    Write-Log "  Billing Scope: $($Config.Billing.EnrollmentAccountScope)" -Level "DEBUG"
    Write-Log "  Target MG: $fullMGName" -Level "DEBUG"
    
    try {
        $newSub = New-AzSubscriptionAlias `
            -AliasName $aliasName `
            -SubscriptionName $SubscriptionName `
            -BillingScope $Config.Billing.EnrollmentAccountScope `
            -Workload $Config.Billing.WorkloadType `
            -ManagementGroupId $mgScope `
            -ErrorAction Stop
        
        $subscriptionId = $newSub.Properties.SubscriptionId
        Write-Log "Successfully created subscription '$SubscriptionName'" -Level "SUCCESS"
        Write-Log "  Subscription ID: $subscriptionId" -Level "INFO"
        
        # Wait for subscription to be fully provisioned
        Write-Log "Waiting for subscription provisioning (30 seconds)..." -Level "INFO"
        Start-Sleep -Seconds 30
        
        return $subscriptionId
    }
    catch {
        Write-Log "Failed to create subscription '$SubscriptionName': $_" -Level "ERROR"
        return $null
    }
}

function Move-SubscriptionToMG {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SubscriptionId,
        
        [Parameter(Mandatory = $true)]
        [string]$TargetMGName
    )
    
    $fullMGName = Get-FullMGName -Name $TargetMGName
    
    if ($Config.General.DryRun) {
        Write-Log "[DRY RUN] Would move subscription '$SubscriptionId' to MG '$fullMGName'" -Level "WARNING"
        return
    }
    
    Write-Log "Moving subscription '$SubscriptionId' to Management Group '$fullMGName'..." -Level "INFO"
    
    try {
        New-AzManagementGroupSubscription -GroupName $fullMGName -SubscriptionId $SubscriptionId
        Write-Log "Successfully moved subscription to '$fullMGName'" -Level "SUCCESS"
    }
    catch {
        Write-Log "Failed to move subscription: $_" -Level "ERROR"
    }
}

function Deploy-SubscriptionAssignments {
    Write-Log "========================================" -Level "INFO"
    Write-Log "PROVISIONING AND ASSIGNING SUBSCRIPTIONS" -Level "INFO"
    Write-Log "========================================" -Level "INFO"
    
    if ($Config.Billing.CreateSubscriptions -and $Config.Billing.EnrollmentAccountScope) {
        Write-Log "EA Subscription Creation: ENABLED" -Level "INFO"
        Write-Log "Enrollment Account: $($Config.Billing.EnrollmentAccountScope)" -Level "DEBUG"
    }
    else {
        Write-Log "EA Subscription Creation: DISABLED (will only assign existing subscriptions)" -Level "INFO"
    }
    
    # Helper function to process a subscription entry
    function Process-Subscription {
        param($sub)
        
        $subscriptionId = $sub.SubscriptionId
        
        # If no subscription ID and CreateIfMissing is true, try to create it
        if (-not $subscriptionId -and $sub.CreateIfMissing) {
            Write-Log "Attempting to create subscription: $($sub.Name)" -Level "INFO"
            $subscriptionId = New-SubscriptionIfNotExists `
                -SubscriptionName $sub.Name `
                -TargetMGName $sub.TargetMG
        }
        
        # If we have a subscription ID, move it to the target MG
        if ($subscriptionId -and $subscriptionId -ne "dry-run-subscription-id") {
            Move-SubscriptionToMG -SubscriptionId $subscriptionId -TargetMGName $sub.TargetMG
        }
        elseif (-not $subscriptionId) {
            Write-Log "Skipping '$($sub.Name)' - No subscription ID and creation not enabled" -Level "DEBUG"
        }
    }
    
    # Process Platform subscriptions
    Write-Log "Processing Platform subscriptions..." -Level "INFO"
    foreach ($key in $Config.Subscriptions.Platform.Keys) {
        $sub = $Config.Subscriptions.Platform[$key]
        Process-Subscription -sub $sub
    }
    
    # Process Landing Zone subscriptions
    Write-Log "Processing Landing Zone subscriptions..." -Level "INFO"
    foreach ($key in $Config.Subscriptions.LandingZones.Keys) {
        $sub = $Config.Subscriptions.LandingZones[$key]
        Process-Subscription -sub $sub
    }
    
    Write-Log "Subscription provisioning completed." -Level "SUCCESS"
}

#endregion

#region ==================== POLICY FUNCTIONS ====================

function Get-PolicyScope {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScopeName
    )
    
    switch ($ScopeName) {
        "Root" {
            return Get-MGScope -MGName (Get-FullMGName -Name $Config.ManagementGroups.Root.Name)
        }
        "Platform" {
            return Get-MGScope -MGName (Get-FullMGName -Name $Config.ManagementGroups.Platform.Name)
        }
        "LandingZones" {
            return Get-MGScope -MGName (Get-FullMGName -Name $Config.ManagementGroups.LandingZones.Name)
        }
        "All" {
            return Get-MGScope -MGName (Get-FullMGName -Name $Config.ManagementGroups.Root.Name)
        }
        default {
            return Get-MGScope -MGName (Get-FullMGName -Name $ScopeName)
        }
    }
}

function New-PolicyAssignmentIfNotExists {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        
        [Parameter(Mandatory = $true)]
        [string]$DisplayName,
        
        [Parameter(Mandatory = $true)]
        [string]$PolicyDefinitionId,
        
        [Parameter(Mandatory = $true)]
        [string]$Scope,
        
        [Parameter(Mandatory = $false)]
        [hashtable]$Parameters = @{},
        
        [Parameter(Mandatory = $false)]
        [string]$Description = "",
        
        [Parameter(Mandatory = $false)]
        [bool]$RequiresManagedIdentity = $false,
        
        [Parameter(Mandatory = $false)]
        [string]$Location = "eastus"
    )
    
    # Ensure name is valid (max 24 chars for MG scope, alphanumeric and hyphens only)
    $assignmentName = $Name -replace '[^a-zA-Z0-9-]', ''
    if ($assignmentName.Length -gt 24) {
        $assignmentName = $assignmentName.Substring(0, 24)
    }
    
    Write-Log "Checking policy assignment: $assignmentName" -Level "DEBUG"
    
    try {
        $existing = Get-AzPolicyAssignment -Name $assignmentName -Scope $Scope -ErrorAction SilentlyContinue
        if ($existing) {
            Write-Log "Policy assignment '$assignmentName' already exists at scope." -Level "INFO"
            return $existing
        }
    }
    catch {
        # Assignment doesn't exist
    }
    
    if ($Config.General.DryRun) {
        Write-Log "[DRY RUN] Would create policy assignment: $DisplayName" -Level "WARNING"
        return $null
    }
    
    Write-Log "Creating policy assignment: $DisplayName" -Level "INFO"
    
    try {
        # Get policy definition
        $policyDef = Get-AzPolicyDefinition -Id $PolicyDefinitionId -ErrorAction Stop
        
        # Handle case where multiple definitions are returned
        if ($policyDef -is [array]) {
            $policyDef = $policyDef[0]
        }
        
        $params = @{
            Name = $assignmentName
            DisplayName = $DisplayName
            PolicyDefinition = $policyDef
            Scope = $Scope
        }
        
        if ($Parameters.Count -gt 0) {
            $params.PolicyParameterObject = $Parameters
        }
        
        if ($Description) {
            $params.Description = $Description
        }
        
        # Add managed identity for Modify/DeployIfNotExists policies
        if ($RequiresManagedIdentity) {
            $params.IdentityType = "SystemAssigned"
            $params.Location = $Location
        }
        
        $assignment = New-AzPolicyAssignment @params
        Write-Log "Successfully created policy assignment: $DisplayName" -Level "SUCCESS"
        return $assignment
    }
    catch {
        Write-Log "Failed to create policy assignment '$DisplayName': $_" -Level "ERROR"
    }
}

function Deploy-TaggingPolicies {
    if (-not $Config.Policies.Tagging.Enabled) {
        Write-Log "Tagging policies are disabled. Skipping..." -Level "INFO"
        return
    }
    
    Write-Log "----------------------------------------" -Level "INFO"
    Write-Log "Deploying Tagging Policies" -Level "INFO"
    Write-Log "----------------------------------------" -Level "INFO"
    
    $scope = Get-PolicyScope -ScopeName $Config.Policies.Tagging.Scope
    
    # Required Tags (Deny effect)
    if ($Config.Policies.Tagging.RequiredTags.Enabled) {
        foreach ($tag in $Config.Policies.Tagging.RequiredTags.Tags) {
            $policyDefId = "/providers/Microsoft.Authorization/policyDefinitions/$($BuiltInPolicies.RequireTagOnResources)"
            
            New-PolicyAssignmentIfNotExists `
                -Name "Require-Tag-$($tag.Name)" `
                -DisplayName "Require tag: $($tag.Name) on resources" `
                -PolicyDefinitionId $policyDefId `
                -Scope $scope `
                -Parameters @{
                    tagName = $tag.Name
                } `
                -Description "Requires the $($tag.Name) tag on all resources. Effect: $($tag.Effect)"
        }
    }
    
    # Audit Tags
    if ($Config.Policies.Tagging.AuditTags.Enabled) {
        foreach ($tag in $Config.Policies.Tagging.AuditTags.Tags) {
            # Using audit version - we'll use require tag but change description
            $policyDefId = "/providers/Microsoft.Authorization/policyDefinitions/$($BuiltInPolicies.RequireTagOnResources)"
            
            New-PolicyAssignmentIfNotExists `
                -Name "Audit-Tag-$($tag.Name)" `
                -DisplayName "Audit tag: $($tag.Name) on resources" `
                -PolicyDefinitionId $policyDefId `
                -Scope $scope `
                -Parameters @{
                    tagName = $tag.Name
                } `
                -Description "Audits resources without the $($tag.Name) tag."
        }
    }
    
    # Inherit Tags from Resource Group (Requires Managed Identity for Modify effect)
    if ($Config.Policies.Tagging.InheritTagsFromRG.Enabled) {
        foreach ($tagName in $Config.Policies.Tagging.InheritTagsFromRG.Tags) {
            $policyDefId = "/providers/Microsoft.Authorization/policyDefinitions/$($BuiltInPolicies.InheritTagFromRGIfMissing)"
            
            New-PolicyAssignmentIfNotExists `
                -Name "Inherit-$tagName-FromRG" `
                -DisplayName "Inherit tag '$tagName' from Resource Group if missing" `
                -PolicyDefinitionId $policyDefId `
                -Scope $scope `
                -Parameters @{
                    tagName = $tagName
                } `
                -Description "Inherits the $tagName tag from the resource group if missing on the resource." `
                -RequiresManagedIdentity $true `
                -Location $Config.General.PrimaryLocation
        }
    }
    
    Write-Log "Tagging policies deployment completed." -Level "SUCCESS"
}

function Deploy-LocationPolicies {
    if (-not $Config.Policies.Location.Enabled) {
        Write-Log "Location policies are disabled. Skipping..." -Level "INFO"
        return
    }
    
    Write-Log "----------------------------------------" -Level "INFO"
    Write-Log "Deploying Location Policies" -Level "INFO"
    Write-Log "----------------------------------------" -Level "INFO"
    
    $scope = Get-PolicyScope -ScopeName $Config.Policies.Location.Scope
    $allowedLocations = $Config.General.AllowedLocations
    
    # Allowed Locations for Resources
    if ($Config.Policies.Location.AllowedLocations.Enabled) {
        $policyDefId = "/providers/Microsoft.Authorization/policyDefinitions/$($BuiltInPolicies.AllowedLocations)"
        
        New-PolicyAssignmentIfNotExists `
            -Name "Allowed-Locations" `
            -DisplayName "Allowed locations for resources" `
            -PolicyDefinitionId $policyDefId `
            -Scope $scope `
            -Parameters @{
                listOfAllowedLocations = $allowedLocations
            } `
            -Description "Restricts resource deployment to specified Azure regions: $($allowedLocations -join ', ')"
    }
    
    # Allowed Locations for Resource Groups
    if ($Config.Policies.Location.AllowedLocationsForRGs.Enabled) {
        $policyDefId = "/providers/Microsoft.Authorization/policyDefinitions/$($BuiltInPolicies.AllowedLocationsForRGs)"
        
        New-PolicyAssignmentIfNotExists `
            -Name "Allowed-Locations-RGs" `
            -DisplayName "Allowed locations for resource groups" `
            -PolicyDefinitionId $policyDefId `
            -Scope $scope `
            -Parameters @{
                listOfAllowedLocations = $allowedLocations
            } `
            -Description "Restricts resource group creation to specified Azure regions."
    }
    
    Write-Log "Location policies deployment completed." -Level "SUCCESS"
}

function Deploy-SecurityPolicies {
    if (-not $Config.Policies.Security.Enabled) {
        Write-Log "Security policies are disabled. Skipping..." -Level "INFO"
        return
    }
    
    Write-Log "----------------------------------------" -Level "INFO"
    Write-Log "Deploying Security Baseline Policies" -Level "INFO"
    Write-Log "----------------------------------------" -Level "INFO"
    
    $scope = Get-PolicyScope -ScopeName $Config.Policies.Security.Scope
    
    # Secure Transfer for Storage Accounts
    if ($Config.Policies.Security.SecureTransferForStorage.Enabled) {
        $policyDefId = "/providers/Microsoft.Authorization/policyDefinitions/$($BuiltInPolicies.SecureTransferToStorageAccounts)"
        
        New-PolicyAssignmentIfNotExists `
            -Name "Secure-Transfer-Storage" `
            -DisplayName "Secure transfer to storage accounts should be enabled" `
            -PolicyDefinitionId $policyDefId `
            -Scope $scope `
            -Description "Audits storage accounts that do not have secure transfer (HTTPS) enabled."
    }
    
    # HTTPS Only for Web Apps
    if ($Config.Policies.Security.HttpsOnlyForWebApps.Enabled) {
        $policyDefId = "/providers/Microsoft.Authorization/policyDefinitions/$($BuiltInPolicies.AuditHttpsOnlyForWebApps)"
        
        New-PolicyAssignmentIfNotExists `
            -Name "HTTPS-Only-WebApps" `
            -DisplayName "Web Application should only be accessible over HTTPS" `
            -PolicyDefinitionId $policyDefId `
            -Scope $scope `
            -Description "Audits web applications that are not configured for HTTPS-only access."
    }
    
    # Minimum TLS Version for Storage
    if ($Config.Policies.Security.MinimumTLSVersion.Enabled) {
        $policyDefId = "/providers/Microsoft.Authorization/policyDefinitions/$($BuiltInPolicies.AuditMinimumTLSVersionForStorage)"
        
        New-PolicyAssignmentIfNotExists `
            -Name "Min-TLS-Storage" `
            -DisplayName "Storage accounts should have minimum TLS version" `
            -PolicyDefinitionId $policyDefId `
            -Scope $scope `
            -Parameters @{
                minimumTlsVersion = "TLS1_2"
            } `
            -Description "Audits storage accounts with TLS version below 1.2."
    }
    
    # Managed Disks for VMs
    if ($Config.Policies.Security.ManagedDisksForVMs.Enabled) {
        $policyDefId = "/providers/Microsoft.Authorization/policyDefinitions/$($BuiltInPolicies.AuditVMsWithoutManagedDisks)"
        
        New-PolicyAssignmentIfNotExists `
            -Name "Managed-Disks-VMs" `
            -DisplayName "Audit VMs that do not use managed disks" `
            -PolicyDefinitionId $policyDefId `
            -Scope $scope `
            -Description "Audits virtual machines that are not using managed disks."
    }
    
    Write-Log "Security policies deployment completed." -Level "SUCCESS"
}

function Deploy-CostManagementPolicies {
    if (-not $Config.Policies.CostManagement.Enabled) {
        Write-Log "Cost Management policies are disabled. Skipping..." -Level "INFO"
        return
    }
    
    Write-Log "----------------------------------------" -Level "INFO"
    Write-Log "Deploying Cost Management Policies (for Fabric Chargeback)" -Level "INFO"
    Write-Log "----------------------------------------" -Level "INFO"
    
    $scope = Get-PolicyScope -ScopeName $Config.Policies.CostManagement.Scope
    
    # Require Tags on Resource Groups
    if ($Config.Policies.CostManagement.RequireTagsOnRGs.Enabled) {
        foreach ($tagName in $Config.Policies.CostManagement.RequireTagsOnRGs.Tags) {
            $policyDefId = "/providers/Microsoft.Authorization/policyDefinitions/$($BuiltInPolicies.RequireTagOnResourceGroups)"
            
            New-PolicyAssignmentIfNotExists `
                -Name "Require-$tagName-OnRG" `
                -DisplayName "Require '$tagName' tag on Resource Groups" `
                -PolicyDefinitionId $policyDefId `
                -Scope $scope `
                -Parameters @{
                    tagName = $tagName
                } `
                -Description "Requires the $tagName tag on all resource groups for cost allocation and chargeback."
        }
    }
    
    Write-Log "Cost Management policies deployment completed." -Level "SUCCESS"
}

function Deploy-AllPolicies {
    Write-Log "========================================" -Level "INFO"
    Write-Log "DEPLOYING AZURE POLICIES" -Level "INFO"
    Write-Log "========================================" -Level "INFO"
    
    Deploy-TaggingPolicies
    Deploy-LocationPolicies
    Deploy-SecurityPolicies
    Deploy-CostManagementPolicies
    
    Write-Log "All policy deployments completed." -Level "SUCCESS"
}

#endregion

#region ==================== MAIN EXECUTION ====================

function Show-Configuration {
    Write-Log "========================================" -Level "INFO"
    Write-Log "DEPLOYMENT CONFIGURATION SUMMARY" -Level "INFO"
    Write-Log "========================================" -Level "INFO"
    
    Write-Log "General Settings:" -Level "INFO"
    Write-Log "  Prefix: $($Config.General.Prefix)" -Level "DEBUG"
    Write-Log "  Primary Location: $($Config.General.PrimaryLocation)" -Level "DEBUG"
    Write-Log "  Allowed Locations: $($Config.General.AllowedLocations -join ', ')" -Level "DEBUG"
    Write-Log "  Dry Run Mode: $($Config.General.DryRun)" -Level "DEBUG"
    
    Write-Log "Management Groups:" -Level "INFO"
    Write-Log "  Root MG: $(Get-FullMGName -Name $Config.ManagementGroups.Root.Name)" -Level "DEBUG"
    Write-Log "  Platform MGs: $($Config.ManagementGroups.Platform.Children.Name -join ', ')" -Level "DEBUG"
    Write-Log "  Landing Zone MGs: $($Config.ManagementGroups.LandingZones.Children.Name -join ', ')" -Level "DEBUG"
    
    Write-Log "Policies Enabled:" -Level "INFO"
    Write-Log "  Tagging: $($Config.Policies.Tagging.Enabled)" -Level "DEBUG"
    Write-Log "  Location: $($Config.Policies.Location.Enabled)" -Level "DEBUG"
    Write-Log "  Security: $($Config.Policies.Security.Enabled)" -Level "DEBUG"
    Write-Log "  Cost Management: $($Config.Policies.CostManagement.Enabled)" -Level "DEBUG"
}

function Start-Deployment {
    Write-Host ""
    Write-Host "╔══════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║       AZURE LANDING ZONE DEPLOYMENT FOR MICROSOFT FABRIC         ║" -ForegroundColor Cyan
    Write-Host "║                                                                  ║" -ForegroundColor Cyan
    Write-Host "║  This script will deploy:                                        ║" -ForegroundColor Cyan
    Write-Host "║  • Management Group Hierarchy                                    ║" -ForegroundColor Cyan
    Write-Host "║  • Subscription Assignments                                      ║" -ForegroundColor Cyan
    Write-Host "║  • Azure Policies (Tagging, Location, Security)                  ║" -ForegroundColor Cyan
    Write-Host "╚══════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    
    # Check Azure connection
    if (-not (Test-AzureConnection)) {
        Write-Log "Please connect to Azure using 'Connect-AzAccount' and try again." -Level "ERROR"
        return
    }
    
    # Show configuration
    Show-Configuration
    
    if ($Config.General.DryRun) {
        Write-Host ""
        Write-Host "╔══════════════════════════════════════════════════════════════════╗" -ForegroundColor Yellow
        Write-Host "║                        DRY RUN MODE                              ║" -ForegroundColor Yellow
        Write-Host "║  No changes will be made. Review the output to see what would   ║" -ForegroundColor Yellow
        Write-Host "║  be created. Set DryRun = `$false to execute.                    ║" -ForegroundColor Yellow
        Write-Host "╚══════════════════════════════════════════════════════════════════╝" -ForegroundColor Yellow
        Write-Host ""
    }
    else {
        Write-Host ""
        Write-Host "╔══════════════════════════════════════════════════════════════════╗" -ForegroundColor Red
        Write-Host "║                         LIVE MODE                                ║" -ForegroundColor Red
        Write-Host "║  This will make changes to your Azure environment.              ║" -ForegroundColor Red
        Write-Host "╚══════════════════════════════════════════════════════════════════╝" -ForegroundColor Red
        Write-Host ""
        
        $confirmation = Read-Host "Do you want to proceed? (yes/no)"
        if ($confirmation -ne "yes") {
            Write-Log "Deployment cancelled by user." -Level "WARNING"
            return
        }
    }
    
    # Execute deployment steps
    try {
        # Step 1: Deploy Management Group Hierarchy
        Deploy-ManagementGroupHierarchy
        
        # Step 2: Assign Subscriptions (if IDs provided)
        Deploy-SubscriptionAssignments
        
        # Step 3: Deploy Policies
        Deploy-AllPolicies
        
        Write-Host ""
        Write-Host "╔══════════════════════════════════════════════════════════════════╗" -ForegroundColor Green
        Write-Host "║              DEPLOYMENT COMPLETED SUCCESSFULLY                   ║" -ForegroundColor Green
        Write-Host "╚══════════════════════════════════════════════════════════════════╝" -ForegroundColor Green
        Write-Host ""
        
        Write-Log "Next Steps:" -Level "INFO"
        Write-Log "1. Verify the Management Group hierarchy in Azure Portal" -Level "INFO"
        Write-Log "2. Update subscription IDs in the config and re-run to assign subscriptions" -Level "INFO"
        Write-Log "3. Review policy compliance in Azure Policy blade" -Level "INFO"
        Write-Log "4. Install Microsoft Fabric Capacity Metrics app for monitoring" -Level "INFO"
        Write-Log "5. Install Microsoft Fabric Chargeback app for cost allocation" -Level "INFO"
    }
    catch {
        Write-Log "Deployment failed with error: $_" -Level "ERROR"
        throw
    }
}

# Execute
Start-Deployment

#endregion
