# Azure Landing Zone Deployment for Microsoft Fabric

This solution deploys a complete Azure Landing Zone (ALZ) hierarchy optimized for Microsoft Fabric workloads, including Management Groups, Subscription assignments, and Azure Policies for governance.

## 📁 Files Overview

| File | Description |
|------|-------------|
| `Deploy-AzureLandingZone.ps1` | Main deployment script with embedded configuration |
| `Config-AzureLandingZone.ps1` | Standalone configuration file (optional) |
| `ALZ-HelperFunctions.ps1` | Utility functions for viewing and managing the hierarchy |

## 🏗️ Architecture Deployed

```
Tenant Root Group
└── Target-ALZ                           ← Root MG
    ├── Target-Platform
    │   ├── Target-Security          → Security Subscription
    │   ├── Target-Management        → Management Subscription
    │   ├── Target-Identity          → Identity Subscription
    │   └── Target-Connectivity      → Connectivity Subscription
    │
    └── Target-LandingZones
        ├── Target-Fabric-BU1        → Fabric Subscription 1
        ├── Target-Fabric-BU2        → Fabric Subscription 2
        └── Target-Fabric-BU3        → Fabric Subscription 3
```

## 📋 Policies Deployed

### Tagging Policies (for Fabric Chargeback)
- **Required Tags (Deny)**: `CostCenter`, `Environment`
- **Audit Tags**: `Owner`, `Application`, `Department`
- **Tag Inheritance**: Automatically inherit tags from Resource Groups

### Location Policies
- **Allowed Locations for Resources**
- **Allowed Locations for Resource Groups**

### Security Baseline Policies
- Secure transfer for storage accounts
- HTTPS only for web apps
- Minimum TLS 1.2 for storage
- Managed disks for VMs

### Cost Management Policies (Landing Zones)
- Require `CostCenter` and `Department` tags on Resource Groups

## 🚀 Quick Start

### Prerequisites

1. **PowerShell 5.1+** or **PowerShell 7+**
2. **Azure PowerShell modules**:
   ```powershell
   Install-Module -Name Az.Accounts -Scope CurrentUser
   Install-Module -Name Az.Resources -Scope CurrentUser
   ```
3. **Azure permissions**: 
   - Management Group Contributor (or Owner) at Tenant Root level
   - User Access Administrator (for policy assignments)

### Step 1: Connect to Azure

```powershell
Connect-AzAccount
```

### Step 2: Customize Configuration

Edit the `$Config` section in `Deploy-AzureLandingZone.ps1`:

```powershell
# Change the organization prefix (default is "Target")
$Config.General.Prefix = "Target"

# Change allowed locations
$Config.General.AllowedLocations = @("eastus", "westeurope")

# Add subscription IDs (get them with: Get-AzSubscription)
$Config.Subscriptions.LandingZones.FabricBU1.SubscriptionId = "your-guid-here"
```

### Step 3: Run in Dry-Run Mode

```powershell
cd c:\Users\ketaanhshah\FabricALZ
.\Deploy-AzureLandingZone.ps1
```

By default, the script runs in **Dry Run mode** - it shows what would be created without making changes.

### Step 4: Execute Deployment

Set `DryRun = $false` in the configuration and run again:

```powershell
$Config.General.DryRun = $false
.\Deploy-AzureLandingZone.ps1
```

## 🏦 Automated Subscription Creation (EA Only)

If your organization has an **Enterprise Agreement (EA)**, the script can automatically create Azure subscriptions.

### Prerequisites

- Enterprise Agreement (EA) or Microsoft Customer Agreement (MCA)
- Owner permissions on EA Enrollment Account
- Billing Reader (minimum) to discover enrollment account

### Step 1: Find Your EA Enrollment Account

```powershell
# Load helper functions and discover EA scope
. .\ALZ-HelperFunctions.ps1
Show-EAEnrollmentAccount
```

This will display your billing scope, e.g.:
```
/providers/Microsoft.Billing/billingAccounts/1234567/enrollmentAccounts/7654321
```

### Step 2: Configure EA Billing in the Script

Edit `Deploy-AzureLandingZone.ps1`:

```powershell
Billing = @{
    CreateSubscriptions = $true
    EnrollmentAccountScope = "/providers/Microsoft.Billing/billingAccounts/YOUR_ID/enrollmentAccounts/YOUR_ENROLLMENT"
    WorkloadType = "Production"  # or "DevTest"
}
```

### Step 3: Enable Subscription Creation per Entry

For each subscription you want to auto-create, set `CreateIfMissing = $true`:

```powershell
FabricBU1 = @{
    Name = "Fabric-BU1-Subscription"
    SubscriptionId = $null          # No existing subscription
    TargetMG = "Fabric-BU1"
    CreateIfMissing = $true         # Will create automatically
}
```

### Step 4: Run Deployment

```powershell
.\Deploy-AzureLandingZone.ps1
```

The script will:
1. Create subscriptions that don't exist (where `CreateIfMissing = $true`)
2. Automatically place them in the correct Management Group
3. Apply policies to the Management Group hierarchy

### Subscription Creation Behavior

| Scenario | Behavior |
|----------|----------|
| `SubscriptionId` provided | Moves existing subscription to target MG |
| `SubscriptionId = $null` + `CreateIfMissing = $false` | Skipped |
| `SubscriptionId = $null` + `CreateIfMissing = $true` + EA configured | Creates new subscription |
| `SubscriptionId = $null` + `CreateIfMissing = $true` + No EA | Warning displayed, skipped |

## ⚙️ Configuration Reference

### General Settings

| Setting | Description | Default |
|---------|-------------|---------|
| `Prefix` | Organization prefix for MG names | `Target` |
| `PrimaryLocation` | Default Azure region | `eastus` |
| `AllowedLocations` | Regions allowed by policy | `eastus, eastus2, westus2, centralus` |
| `DryRun` | Preview mode (no changes) | `$true` |
| `VerboseLogging` | Detailed output | `$true` |

### EA Billing Settings (for Subscription Creation)

| Setting | Description | Default |
|---------|-------------|---------|
| `CreateSubscriptions` | Enable automated subscription creation | `$false` |
| `EnrollmentAccountScope` | EA billing scope (required for creation) | `$null` |
| `WorkloadType` | Production or DevTest | `Production` |

### Subscription Settings

Each subscription entry supports:

| Property | Description |
|----------|-------------|
| `Name` | Display name for the subscription |
| `SubscriptionId` | Existing subscription GUID (or `$null` to create) |
| `TargetMG` | Target Management Group name |
| `CreateIfMissing` | Set to `$true` to auto-create if no ID provided |

### Policy Toggles

Each policy category can be enabled/disabled:

```powershell
$Config.Policies.Tagging.Enabled = $true         # Tagging policies
$Config.Policies.Location.Enabled = $true        # Location restrictions
$Config.Policies.Security.Enabled = $true        # Security baseline
$Config.Policies.CostManagement.Enabled = $true  # Cost allocation tags
```

### Individual Policy Control

Each sub-policy can be toggled:

```powershell
# Example: Disable HTTPS-only for web apps
$Config.Policies.Security.HttpsOnlyForWebApps.Enabled = $false

# Example: Change effect from Deny to Audit
$Config.Policies.Tagging.RequiredTags.Tags = @(
    @{ Name = "CostCenter"; Effect = "Audit" }  # Changed from Deny
)
```

## 🔧 Helper Functions

Load the helper functions:

```powershell
. .\ALZ-HelperFunctions.ps1
```

### Available Commands

```powershell
# Launch interactive menu (9 options)
Start-InteractiveMenu

# View Management Group hierarchy
Show-ManagementGroupHierarchy
Show-ManagementGroupHierarchy -RootGroupName "Target-ALZ"

# View policy assignments
Show-PolicyAssignments -ManagementGroupName "Target-ALZ"

# Check policy compliance
Show-PolicyCompliance -ManagementGroupName "Target-ALZ"

# List all subscriptions
Show-Subscriptions

# Get EA Enrollment Account for subscription creation
Show-EAEnrollmentAccount

# Remove policies from a Management Group (use -WhatIf first!)
Remove-PolicyAssignments -ManagementGroupName "Target-ALZ" -WhatIf
Remove-PolicyAssignments -ManagementGroupName "Target-ALZ"

# Remove entire MG hierarchy (use -WhatIf first!)
Remove-ManagementGroupHierarchy -RootGroupName "Target-ALZ" -WhatIf
Remove-ManagementGroupHierarchy -RootGroupName "Target-ALZ"
```

### Interactive Menu Options

| # | Option | Description |
|---|--------|-------------|
| 1 | Check Prerequisites | Verify Azure connection and modules |
| 2 | Show MG Hierarchy | Display Management Group tree |
| 3 | Show Policy Assignments | List policies at a MG scope |
| 4 | Show Policy Compliance | Check compliance status |
| 5 | List Subscriptions | Show all Azure subscriptions |
| 6 | Show EA Enrollment Account | Get billing scope for subscription creation |
| 7 | Run Deployment Script | Execute the main deployment |
| 8 | Remove Policy Assignments | Preview policy removal (WhatIf) |
| 9 | Remove MG Hierarchy | Preview hierarchy removal (WhatIf) |
| Q | Quit | Exit the menu |

## 📊 Fabric Chargeback Integration

This deployment supports the Microsoft Fabric Chargeback model:

### Azure-Level Cost Tracking
- **Tags on resources**: `CostCenter`, `Department`, `Environment`
- **Tag inheritance**: Automatically applied from Resource Groups
- **Azure Cost Management**: View costs by tag in Azure Portal

### Fabric-Level Cost Attribution
After deployment, install the **Fabric Chargeback App** to track:
- CU consumption per workspace
- Usage by workload type
- Cost allocation by department

Reference: [Microsoft Fabric Chargeback App](https://learn.microsoft.com/en-us/fabric/enterprise/chargeback-app)

## 🔄 Modifying the Deployment

### Add a New Business Unit

1. Add the Management Group:
```powershell
$Config.ManagementGroups.LandingZones.Children += @(
    @{ Name = "Fabric-BU4"; DisplayName = "Fabric BU4 - Finance" }
)
```

2. Add the Subscription mapping:
```powershell
$Config.Subscriptions.LandingZones.FabricBU4 = @{
    Name           = "Fabric-Subscription-4"
    SubscriptionId = "your-subscription-guid"
    TargetMG       = "Fabric-BU4"
}
```

3. Re-run the deployment script.

### Change Policy Scope

Policies can be applied at different levels:
- `"Root"` - Applies to entire ALZ (Platform + Landing Zones)
- `"Platform"` - Only Platform MGs
- `"LandingZones"` - Only Landing Zone MGs (Fabric BUs)

```powershell
$Config.Policies.Tagging.Scope = "LandingZones"  # Only apply to Fabric subscriptions
```

## 🧹 Cleanup

To remove the deployment (use with caution):

```powershell
# Preview what would be removed
. .\ALZ-HelperFunctions.ps1
Remove-ManagementGroupHierarchy -RootGroupName "Target-ALZ" -WhatIf

# Actually remove (requires typing 'DELETE' to confirm)
Remove-ManagementGroupHierarchy -RootGroupName "Target-ALZ"
```

## 📚 References

- [Azure Landing Zones](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/landing-zone/)
- [Azure Policy Built-in Definitions](https://learn.microsoft.com/en-us/azure/governance/policy/samples/built-in-policies)
- [Microsoft Fabric Governance](https://learn.microsoft.com/en-us/fabric/governance/governance-compliance-overview)
- [Fabric Capacity Metrics App](https://learn.microsoft.com/en-us/fabric/enterprise/metrics-app)
- [Fabric Chargeback App](https://learn.microsoft.com/en-us/fabric/enterprise/chargeback-app)

## ⚠️ Important Notes

1. **Management Group creation** may take a few minutes to propagate
2. **Policy compliance** data takes up to 24 hours to populate
3. **Subscription movement** requires appropriate RBAC permissions
4. **Subscription creation** requires EA Owner on Enrollment Account
5. **New subscriptions** take ~30 seconds to provision before assignment
6. **Always test** in Dry Run mode before executing in production
7. **Backup** existing configurations before making changes

## 🔐 Required Permissions

| Action | Required Permission |
|--------|---------------------|
| Create Management Groups | Management Group Contributor at Tenant Root |
| Assign Policies | Resource Policy Contributor at MG scope |
| Move Subscriptions | Owner on subscription + MG Contributor |
| Create Subscriptions | Owner on EA Enrollment Account |
| View EA Billing | Billing Reader or higher |
