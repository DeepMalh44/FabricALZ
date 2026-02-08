<#
.SYNOPSIS
    Configuration file for Azure Landing Zone deployment.
    
.DESCRIPTION
    This file contains all configurable parameters for the ALZ deployment.
    Modify this file to customize your deployment without changing the main script.
    
    To use: Dot-source this file before running the main script, or
    copy the $Config variable into the main script's configuration section.
    
.NOTES
    Version: 1.0
    Last Updated: 2026-02-08
#>

#region ==================== EDITABLE CONFIGURATION ====================

$Config = @{
    
    #══════════════════════════════════════════════════════════════════════
    # GENERAL SETTINGS
    # These settings control the overall deployment behavior
    #══════════════════════════════════════════════════════════════════════
    General = @{
        # Prefix for all Management Group names (e.g., "Target" creates "Target-Platform")
        # CHANGE THIS to your organization name
        Prefix = "Target"
        
        # Primary Azure region for deployments
        PrimaryLocation = "eastus"
        
        # List of allowed Azure regions (used by Location policies)
        # Add or remove regions based on your requirements
        AllowedLocations = @(
            "eastus"
            "eastus2"
            "westus2"
            "centralus"
            # "westeurope"
            # "northeurope"
        )
        
        # Enable detailed logging output
        VerboseLogging = $true
        
        # DRY RUN MODE
        # Set to $true to see what would be created without making changes
        # Set to $false to execute the actual deployment
        DryRun = $true
    }
    
    #══════════════════════════════════════════════════════════════════════
    # MANAGEMENT GROUP HIERARCHY
    # Define your management group structure here
    # Names should be alphanumeric with hyphens (no spaces)
    #══════════════════════════════════════════════════════════════════════
    ManagementGroups = @{
        
        # Root Management Group (directly under Tenant Root Group)
        Root = @{
            Name        = "ALZ"                  # Internal name (no spaces)
            DisplayName = "Target ALZ"           # Display name in Azure Portal
        }
        
        # Platform Management Group and its children
        Platform = @{
            Name        = "Platform"
            DisplayName = "Platform"
            
            # Platform child management groups
            # Modify or add children as needed
            Children = @(
                @{ Name = "Security";     DisplayName = "Security" }
                @{ Name = "Management";   DisplayName = "Management" }
                @{ Name = "Identity";     DisplayName = "Identity" }
                @{ Name = "Connectivity"; DisplayName = "Connectivity" }
            )
        }
        
        # Landing Zones Management Group and its children
        LandingZones = @{
            Name        = "LandingZones"
            DisplayName = "Landing zones"
            
            # Landing zone child management groups
            # These are your Fabric Business Units
            # Add, remove, or rename as needed
            Children = @(
                @{ Name = "Fabric-BU1"; DisplayName = "Fabric BU1" }
                @{ Name = "Fabric-BU2"; DisplayName = "Fabric BU2" }
                @{ Name = "Fabric-BU3"; DisplayName = "Fabric BU3" }
                # Add more BUs as needed:
                # @{ Name = "Fabric-BU4"; DisplayName = "Fabric BU4" }
            )
        }
    }
    
    #══════════════════════════════════════════════════════════════════════
    # SUBSCRIPTION ASSIGNMENTS
    # Map existing subscriptions to Management Groups
    # 
    # IMPORTANT: 
    # - Set SubscriptionId to the actual GUID of your subscription
    # - Set to $null if the subscription doesn't exist yet (will be skipped)
    # - You can find subscription IDs in Azure Portal or via:
    #   Get-AzSubscription | Select-Object Name, Id
    #══════════════════════════════════════════════════════════════════════
    Subscriptions = @{
        
        # Platform subscriptions (shared services)
        Platform = @{
            Security = @{
                Name           = "Security-Subscription"
                SubscriptionId = $null  # Example: "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
                TargetMG       = "Security"
            }
            Management = @{
                Name           = "Management-Subscription"
                SubscriptionId = $null
                TargetMG       = "Management"
            }
            Identity = @{
                Name           = "Identity-Subscription"
                SubscriptionId = $null
                TargetMG       = "Identity"
            }
            Connectivity = @{
                Name           = "Connectivity-Subscription"
                SubscriptionId = $null
                TargetMG       = "Connectivity"
            }
        }
        
        # Landing Zone subscriptions (Fabric workloads)
        LandingZones = @{
            FabricBU1 = @{
                Name           = "Fabric-Subscription-1"
                SubscriptionId = $null  # Set your subscription ID here
                TargetMG       = "Fabric-BU1"
            }
            FabricBU2 = @{
                Name           = "Fabric-Subscription-2"
                SubscriptionId = $null
                TargetMG       = "Fabric-BU2"
            }
            FabricBU3 = @{
                Name           = "Fabric-Subscription-3"
                SubscriptionId = $null
                TargetMG       = "Fabric-BU3"
            }
        }
    }
    
    #══════════════════════════════════════════════════════════════════════
    # AZURE POLICY CONFIGURATION
    # Enable or disable individual policies
    # Configure policy parameters and scope
    #══════════════════════════════════════════════════════════════════════
    Policies = @{
        
        #──────────────────────────────────────────────────────────────────
        # TAGGING POLICIES
        # Essential for cost allocation and governance
        #──────────────────────────────────────────────────────────────────
        Tagging = @{
            # Master switch - set to $false to disable all tagging policies
            Enabled = $true
            
            # Where to apply these policies
            # Options: "Root" (all MGs), "Platform", "LandingZones"
            Scope = "Root"
            
            # Tags that BLOCK deployment if missing (Deny effect)
            RequiredTags = @{
                Enabled = $true
                Tags = @(
                    @{ Name = "CostCenter";   Effect = "Deny" }
                    @{ Name = "Environment";  Effect = "Deny" }
                    # Add more required tags:
                    # @{ Name = "Project"; Effect = "Deny" }
                )
            }
            
            # Tags that report non-compliance but don't block (Audit effect)
            AuditTags = @{
                Enabled = $true
                Tags = @(
                    @{ Name = "Owner";       Effect = "Audit" }
                    @{ Name = "Application"; Effect = "Audit" }
                    @{ Name = "Department";  Effect = "Audit" }
                )
            }
            
            # Automatically inherit tags from Resource Group to resources
            InheritTagsFromRG = @{
                Enabled = $true
                Tags = @(
                    "CostCenter"
                    "Environment"
                    "Department"
                )
            }
        }
        
        #──────────────────────────────────────────────────────────────────
        # LOCATION/REGION POLICIES
        # Control where resources can be deployed
        #──────────────────────────────────────────────────────────────────
        Location = @{
            Enabled = $true
            Scope = "Root"
            
            # Restrict resource deployment to specific regions
            AllowedLocations = @{
                Enabled = $true
                # Uses General.AllowedLocations values
            }
            
            # Restrict resource group creation to specific regions
            AllowedLocationsForRGs = @{
                Enabled = $true
            }
        }
        
        #──────────────────────────────────────────────────────────────────
        # SECURITY BASELINE POLICIES
        # Enforce security best practices
        #──────────────────────────────────────────────────────────────────
        Security = @{
            Enabled = $true
            Scope = "Root"
            
            # Microsoft Defender for Cloud
            DefenderForCloud = @{
                Enabled          = $true
                AutoProvisioning = $true
            }
            
            # Require HTTPS for storage accounts
            SecureTransferForStorage = @{
                Enabled = $true
                Effect  = "Audit"  # Options: "Audit", "Deny"
            }
            
            # Require HTTPS for web apps
            HttpsOnlyForWebApps = @{
                Enabled = $true
                Effect  = "Audit"
            }
            
            # Require TLS 1.2 minimum
            MinimumTLSVersion = @{
                Enabled = $true
                Effect  = "Audit"
            }
            
            # Audit VMs without managed disks
            ManagedDisksForVMs = @{
                Enabled = $true
                Effect  = "Audit"
            }
        }
        
        #──────────────────────────────────────────────────────────────────
        # COST MANAGEMENT POLICIES
        # Essential for Fabric chargeback model
        #──────────────────────────────────────────────────────────────────
        CostManagement = @{
            Enabled = $true
            
            # Apply only to Landing Zones (where Fabric capacities live)
            Scope = "LandingZones"
            
            # Require tags on Resource Groups for cost allocation
            RequireTagsOnRGs = @{
                Enabled = $true
                Tags = @(
                    "CostCenter"
                    "Department"
                )
            }
        }
    }
}

#endregion

#region ==================== QUICK CUSTOMIZATION EXAMPLES ====================
<#
═══════════════════════════════════════════════════════════════════════════════
EXAMPLE 1: Change Organization Prefix
═══════════════════════════════════════════════════════════════════════════════
$Config.General.Prefix = "MyCompany"

This creates Management Groups like:
- MyCompany-Target-ALZ
- MyCompany-Platform
- MyCompany-LandingZones

═══════════════════════════════════════════════════════════════════════════════
EXAMPLE 2: Add More Fabric Business Units
═══════════════════════════════════════════════════════════════════════════════
$Config.ManagementGroups.LandingZones.Children += @(
    @{ Name = "Fabric-BU4"; DisplayName = "Fabric BU4 - Finance" }
    @{ Name = "Fabric-BU5"; DisplayName = "Fabric BU5 - Marketing" }
)

$Config.Subscriptions.LandingZones.FabricBU4 = @{
    Name           = "Fabric-Subscription-4"
    SubscriptionId = "your-subscription-id"
    TargetMG       = "Fabric-BU4"
}

═══════════════════════════════════════════════════════════════════════════════
EXAMPLE 3: Disable Security Policies (not recommended for production)
═══════════════════════════════════════════════════════════════════════════════
$Config.Policies.Security.Enabled = $false

═══════════════════════════════════════════════════════════════════════════════
EXAMPLE 4: Add European Regions
═══════════════════════════════════════════════════════════════════════════════
$Config.General.AllowedLocations = @(
    "eastus", "westeurope", "northeurope", "uksouth"
)

═══════════════════════════════════════════════════════════════════════════════
EXAMPLE 5: Change Tagging Policy from Deny to Audit
═══════════════════════════════════════════════════════════════════════════════
$Config.Policies.Tagging.RequiredTags.Tags = @(
    @{ Name = "CostCenter"; Effect = "Audit" }  # Changed from Deny
)

═══════════════════════════════════════════════════════════════════════════════
EXAMPLE 6: Assign Existing Subscriptions
═══════════════════════════════════════════════════════════════════════════════
# Get your subscription IDs first:
# Get-AzSubscription | Select-Object Name, Id

$Config.Subscriptions.LandingZones.FabricBU1.SubscriptionId = "12345678-1234-1234-1234-123456789012"
$Config.Subscriptions.Platform.Security.SubscriptionId = "87654321-4321-4321-4321-210987654321"
#>
#endregion

# Export the configuration
Write-Host "Configuration loaded. Use `$Config variable to access settings." -ForegroundColor Green
Write-Host "To deploy, run: .\Deploy-AzureLandingZone.ps1" -ForegroundColor Cyan
