<#
.SYNOPSIS
Assigns M365 license and adds cloud group memberships via Microsoft Graph.

.DESCRIPTION
- Connects to Microsoft Graph interactively.
- Validates license availability; assigns only if there are free units.
- Sets UsageLocation (required for licensing).
- Adds to All Employees and either Sensapure Team (HQ) or Production (Warehouse).
- Safe: no secrets in source; relies on delegated auth.

.PARAMETER UserPrincipalName
Target user's UPN (e.g., gamaral@ad.sensapure.com or primary SMTP).

.PARAMETER OfficeType
Either 'HQ' or 'Warehouse' to decide between Sensapure Team vs Production groups.

.PARAMETER SkuPartNumber
License SKU String ID (default: O365_BUSINESS_PREMIUM for Business Standard).

.PARAMETER SkuId
License GUID (optional). If provided, overrides SkuPartNumber.

.PARAMETER UsageLocation
Two-letter country code for licensing (default: US).

.PARAMETER DryRun
Preview actions without making changes.

.NOTES
Author: Gabriel Amaral (with M365 Copilot)
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$UserPrincipalName,

    [ValidateSet('HQ','Warehouse')]
    [string]$OfficeType,

    [string]$SkuPartNumber = 'O365_BUSINESS_PREMIUM',   # Business Standard per Microsoft SKU table
    [string]$SkuId,                                     # Optional override

    [string]$UsageLocation = 'US',
    [switch]$DryRun
)

function Connect-GraphSafe {
    # Minimal scopes for reads and license assignment + group membership
    $scopes = @(
        'User.ReadWrite.All',        # update UsageLocation
        'Organization.Read.All',     # read SKUs
        'Directory.ReadWrite.All',   # add group members
        'Group.ReadWrite.All'
    )
    Connect-MgGraph -Scopes $scopes
}

function Resolve-Sku {
    param([string]$SkuPartNumber, [string]$SkuId)
    $skus = Get-MgSubscribedSku -All
    if ($SkuId) {
        $match = $skus | Where-Object { $_.SkuId -eq $SkuId }
    } else {
        $match = $skus | Where-Object { $_.SkuPartNumber -eq $SkuPartNumber }
    }
    if (-not $match) { throw "SKU not found in tenant. PartNumber='$SkuPartNumber' SkuId='$SkuId'" }
    $enabled  = $match.PrepaidUnits.Enabled
    $consumed = $match.ConsumedUnits
    $available = [int]$enabled - [int]$consumed
    [PSCustomObject]@{
        SkuId      = $match.SkuId
        PartNumber = $match.SkuPartNumber
        Enabled    = $enabled
        Consumed   = $consumed
        Available  = $available
    }
}

function Ensure-UsageLocation {
    param([string]$UserId, [string]$Location)
    $u = Get-MgUser -UserId $UserId -Property Id,DisplayName,UserPrincipalName,UsageLocation
    if (-not $u.UsageLocation) {
        Update-MgUser -UserId $UserId -UsageLocation $Location
        Write-Host "Set UsageLocation=$Location for $($u.UserPrincipalName)" -ForegroundColor Green
    }
}

function Assign-License-IfAvailable {
    param([string]$UserId, [guid]$SkuId)
    $sku = Get-MgSubscribedSku -SubscribedSkuId $SkuId
    $avail = [int]$sku.PrepaidUnits.Enabled - [int]$sku.ConsumedUnits
    if ($avail -le 0) {
        Write-Warning "No available licenses for SKU $($sku.SkuPartNumber) ($SkuId). Skipping assignment."
        return $false
    }
    Set-MgUserLicense -UserId $UserId -AddLicenses @{SkuId = $SkuId} -RemoveLicenses @()
    Write-Host "Assigned license $($sku.SkuPartNumber) to user." -ForegroundColor Green
    return $true
}

function Get-GroupIdByMail {
    param([string]$MailAddress)
    # Find a cloud group by its primary mail (works for M365 groups, DLs that are Entra objects)
    $g = Get-MgGroup -Filter "mail eq '$MailAddress'" -Property Id,DisplayName,Mail
    if (-not $g) { throw "Group with mail '$MailAddress' not found." }
    $g.Id
}

function Add-User-To-Group {
    param([string]$GroupId, [string]$UserId)
    # Add member reference
    New-MgGroupMember -GroupId $GroupId -BodyParameter @{ "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$UserId" } | Out-Null
    Write-Host "Added user to group $GroupId" -ForegroundColor Green
}

# ----- Begin -----
Connect-GraphSafe

# Resolve user
$user = Get-MgUser -UserId $UserPrincipalName -Property Id,DisplayName,UserPrincipalName,Mail
if (-not $user) { throw "User '$UserPrincipalName' not found in Entra ID." }

# Resolve SKU
$skuInfo = Resolve-Sku -SkuPartNumber $SkuPartNumber -SkuId $SkuId
Write-Host ("License SKU resolved: " + $skuInfo.PartNumber + " | SkuId=" + $skuInfo.SkuId + " | Available=" + $skuInfo.Available) -ForegroundColor Cyan

# Resolve groups
$allEmployeesId   = Get-GroupIdByMail -MailAddress 'AllEmployees@sensapureflavors.com'
$hqId             = Get-GroupIdByMail -MailAddress 'sensapureteam@sensapureflavors.com'
$warehouseId      = Get-GroupIdByMail -MailAddress 'production@sensapure.com'

Write-Host "Groups resolved. AllEmployees=$allEmployeesId | HQ=$hqId | Warehouse=$warehouseId" -ForegroundColor Cyan

if ($DryRun) {
    Write-Warning "DryRun — no changes will be made."
    return
}

# UsageLocation required before licensing
Ensure-UsageLocation -UserId $user.Id -Location $UsageLocation

# Assign license only if available
$null = Assign-License-IfAvailable -UserId $user.Id -SkuId $skuInfo.SkuId

# Add to All Employees
Add-User-To-Group -GroupId $allEmployeesId -UserId $user.Id

# Branch group
if ($OfficeType -eq 'HQ') {
    Add-User-To-Group -GroupId $hqId -UserId $user.Id
} elseif ($OfficeType -eq 'Warehouse') {
    Add-User-To-Group -GroupId $warehouseId -UserId $user.Id
}

Write-Host "Cloud onboarding completed for $($user.UserPrincipalName)." -ForegroundColor Green