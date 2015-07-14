################################################################
# A powershell script for recompiling, regenerating il and syncing
# a local development instance.
#
# Usage:
# .\rebuildAx.ps1
#
################################################################
# Methods
################################################################

function Test-AdministratorPrivileges {
    $identity  = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal( $identity )
    $principal.IsInRole( [System.Security.Principal.WindowsBuiltInRole]::Administrator )
}

function Execute-CompileAndSynchronize 
{
    param(
        [Parameter(Mandatory=$true)]
        [string] $axClientCommand,
        [Parameter(Mandatory=$true)]
        [string] $logFile
        )

    $xmlFile = @"
<?xml version="1.0" ?>
<AxaptaAutoRun logFile="$logFile"  logToScreen="false" exitWhenDone="true"> 
    <CompileIL />
    <Synchronize />
    <PreventCheckList />  
</AxaptaAutoRun>
"@

    $xmlFileLocation = "$PSScriptRoot\AutoRun_CompileIlAndSync.xml"

    if(Test-Path -Path "$xmlFileLocation")
    {
        Remove-Item -Path $xmlFileLocation
    }

    $xmlFile | Out-File -FilePath "$xmlFileLocation"

    & "$axClientCommand" "-minimize" "-startupcmd=AutoRun_$xmlFileLocation" | Out-String

    if($LastExitCode -ne 0) {
            throw "An error occurred whilst executing '$axClientCommand'"
    }       

    Remove-Item -Path "$xmlFileLocation"
}

################################################################
# Configuration
################################################################
$axServerInstallPath = "C:\Program Files\Microsoft Dynamics AX\60\Server\MicrosoftDynamicsAX\bin"
$axClientInstallPath = "C:\Program Files (x86)\Microsoft Dynamics AX\60\Client\Bin"
$axBuild = "$axServerInstallPath\AXBuild.exe"

# Import AX scripts
Import-Module "C:\Program Files\Microsoft Dynamics AX\60\ManagementUtilities\Modules\AXUtilLib.Powershell\AXUtilLib.PowerShell.dll"
Import-Module "C:\Program Files\Microsoft Dynamics AX\60\ManagementUtilities\Modules\Microsoft.Dynamics.AX.Framework.Management\Microsoft.Dynamics.AX.Framework.Management.dll"
##################################################################
# Main Application
##################################################################
 
If(!(Test-AdministratorPrivileges))
{
    Write-Host -ForegroundColor Red "Please run this script with admin privileges"
    return
}

# Step 1: Stop AOS
Stop-Service -Name 'AOS60$01'

# Step 2: Blow away XPIL etc..
Write-Host "Clearing XPPIL cache"
if(Test-Path -Path "$axServerInstallPath\XPPIL") {
    Remove-Item -Path "$axServerInstallPath\XPPIL" -Recurse
}

# Step 2: Install new model

install-axmodel –File “$PSSCriptRoot\K3 Demand Forecasting R5.1 for AX2012 R3 CU8.axmodel” –Conflict Overwrite

# Step 3: AXBuild
Write-Host "Running AXBuild"
& $axBuild "xppcompileall" "/s=01" "/altbin=$axClientInstallPath" "/compiler=$axServerInstallPath\ax32serv.exe" | Out-String

if($LastExitCode -ne 0) {
    throw "An unexpected error occured whilst running the axBuild process"
}

# Step 4: Restart AOS
Start-Service -Name 'AOS60$01'

# Step 5: CompileIL/Sync
Execute-CompileAndSynchronize -axClientCommand "$axClientInstallPath\ax32.exe" -logFile "$PSScriptRoot\compileilandsync.log"

Write-Host "Rebuild complete!"
Pop-Location