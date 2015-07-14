 Param(
    [ValidateSet("local", "dev", "uat", "live", ignoreCase = $true)]
    [Parameter(Mandatory=$true)]
    [string] $Target,
    [switch] $RunHeadless
)



Unblock-File -Path $PSScriptRoot\CodeCrib.Ax.*.dll
Add-Type -Pat $PSScriptRoot\CodeCrib.AX.Client.dll
Import-Module $PSScriptRoot\CodeCrib.AX.Config.PowerShell.dll
Import-Module "C:\Program Files\Microsoft Dynamics AX\60\ManagementUtilities\Modules\AXUtilLib.Powershell\AXUtilLib.PowerShell.dll"
Import-Module "C:\Program Files\Microsoft Dynamics AX\60\ManagementUtilities\Modules\Microsoft.Dynamics.AX.Framework.Management\Microsoft.Dynamics.AX.Framework.Management.dll"
Import-Module $PSScriptRoot\axhelpers.psm1
###################################################################
# Script wide config
###################################################################
$scriptDirectory = $PSScriptRoot
$modelDatabaseName = "MicrosoftDynamicsAX_model"
$axUpdatePortalExeLocation = "AxUpdatePortal.exe"

$environments = @{
    "LOCAL" = @{
        "aosServers" = @( "localhost" )
        "aosServiceUser" = "CONNECT\AXDEVAOS"
        "enterprisePortalUrl" = ""
        "reportingServers" = @( "localhost" )
        "databaseServer" = ".\AXDEV"        
        "configuration" = "build-client.axc"
    }
    "DEV" = @{
        "aosServers" = @( "AX-DEV-AOS-01" )
        "aosServiceUser" = "CONNECT\AXDEVAOS" # TODO: Correct this
        "enterprisePortalUrl" = ""
        "reportingServers" = @( "AX-DEV-RS-01" ) 
        "databaseServer" = @( "AX-UAT-SQL-01\sql_ax_dev1" )
        "configuration" = "DEV-client.axc"
    }
    "UAT" = @{
        "aosServers" = @( "AX-UAT-AOS-01", "AX-UAT-BAT-01" )
        "aosServiceUser" = "CONNECT\AXDEVAOS" # TODO: Correct this
        "enterprisePortalUrl" = ""
        "reportingServers" = @( "AX-UAT-RS-01" ) 
        "databaseServer" = @( "AX-UAT-SQL-01\sql_ax_uat1" )
        "configuration" = "UAT-client.axc"
    }   
    "LIVE" = @{
        "aosServers" = @( "AX-AOS-01", "AX-AOS-02", "AX-AOS-03", "AX-AOS-04", "AX-AOS-BAT-01" )
        "aosServiceUser" = "CONNECT\AXDEVAOS" # TODO: Correct this
        "enterprisePortalUrl" = ""
        "reportingServers" = @( "AX-RS-01" ) 
        "databaseServer" = @( "AX-SQL-01\sql_ax1" )
        "configuration" = "production.axc"
    }
};

###################################################################
# functions...
###################################################################

function Reject-NewAxClients
{
    if($RunHeadless.IsPresent)  { return }

    Write-Host "*************************************************************************************************************"
    Write-Host -ForegroundColor Yellow "This is a manual step."
    Write-Host "Please reject new connections from all AOS instances."
    Write-Host "Please press enter when this has been completed"
    Write-Host
    pause
}

function Accept-NewAxClients
{
    if($RunHeadless.IsPresent)  { return }

    Write-Host "*************************************************************************************************************"
    Write-Host -ForegroundColor Yellow "This is a manual step."
    Write-Host "Within AX, please do to Administration > Online users"
    Write-Host "On the Server Instances tab, select each AOS instance, and then click the 'Accept new clients' button"
    Write-Host
    pause
}

function Abort-IfUnmetDependencies
{
    $clientBinDir = "C:\Program Files (x86)\Microsoft Dynamics AX\60\Client\Bin"
    
    if((Test-Path -Path "$clientBinDir\ax32.exe") -eq $false)
    {
        Write-Host -ForegroundColor Red "Error: The AX client is not installed on this machine. It is required to perform database synchronisation"
        exit -1
    }
}

function Restart-ReportingServers
{
    Param( 
        [Parameter(Mandatory=$true)]
        [string[]] $servers
    )

    foreach($server in $servers)
    {
        $service = Get-Service -Name 'ReportServer$AXDEV' -ComputerName $server

        if(($service | Select -ExpandProperty "Status") -eq "Running")
        {
            $service | Set-Service -Status Stopped
            $service | Set-Service -Status Running
        }  
    }
}

function Stop-AosInstances
{
    Param( 
        [Parameter(Mandatory=$true)]
        [string[]] $servers       
    )


    foreach($server in $servers)
    {        
        $service = Get-Service -Name 'AOS60$01' -ComputerName $server

        if($service.Status -eq "Running")
        {
            Stop-service -InputObject $service
        }        
    }
}

function Start-AosInstances
{
    Param( 
        [Parameter(Mandatory=$true)]
        [string[]] $servers
    )

    foreach($server in $servers)
    {        
        $service = Get-Service -Name 'AOS60$01' -ComputerName $server

        if($service.Status -eq "Stopped")
        {
            Start-Service -InputObject $service 
        }        
    }
}

function Get-LatestModelStore
{    
    $matchingStores = [string[]] (Get-ChildItem -Path "${scriptDirectory}" -filter *.axmodelstore | Select -ExpandProperty Name)

    if($matchingStores.Length -eq 0)
    {
        throw "unable to find any AX Model stores in the current directory, aborting"
    }

    return ([string[]]($matchingStores | Sort-Object -Descending))[0]
}

function Deploy-EnterprisePortalUpdates 
{
    Param(
        [string] $url = ""
    )

    if($url.Length -gt 0)
    {
       & "$axUpdatePortalExeLocation" -updateall -websiteurl $url
    }
}

function CleanupMetaData
{
    param
    (
        [string] $Server,
        [string] $Database,
        [string] $aosServiceUser,
        [string] $tempSchema,
        [string] $backupSchema
    )

    if($RunHeadless.IsPresent -eq $false)
    {
        Write-Host "Do you wish to remove the backup schema? [Y/N]"
        $answer = Read-Host
    }

    if($RunHeadless.IsPresent -or $answer.ToUpperInvariant() -eq "Y")
    {
        Write-Host "Dropping backup schema"
        Write-Host "Running Initialize-AXModelStore -AOSAccount $aosServiceUser -Drop $backupSchema -Server $Server -Database $Database -NoPrompt"
        Initialize-AXModelStore -AOSAccount $aosServiceUser -Drop $backupSchema -Server $Server -Database $Database -NoPrompt
    } 
    else 
    {
        Write-Host "Please remember to manually drop the schema '$backupSchemaName' before the next deployment!"
    }

    Write-Host "Dropping the temporary schema"
    Write-Host "Running Initialize-AXModelStore -AOSAccount $aosServiceUser -Drop $tempSchema -Server $Server -Database $Database -NoPrompt"
    Initialize-AXModelStore -AOSAccount $aosServiceUser -Drop $tempSchema -Server $Server -Database $Database -NoPrompt        
} 

function Write-AosShutdownImminentWarning
{
    if($RunHeadless.IsPresent) { return }

    Write-Host "The AOS instances now need to be shut-down before deployment can continue"
    Write-Host -ForegroundColor Red "WARNING: This will terminate all connections to Microsoft Dynamics AX!"
    Write-Host 
    $answer = Read-Host -Prompt "Do you wish to continue? [Y/N]"

    if($answer.ToUpperInvariant() -ne "Y")
    {
        Write-Host -ForegroundColor Yellow "deployment aborted, cleaning up meta-data."
        CleanupMetaData -Server $dbServer -Database $modelDatabaseName -aosServiceUser $aosUser -tempSchema $schema -backupSchema $backupSchema
        exit -1;
    }
}

function Create-RoleCentres
{
    if($RunHeadless.IsPresent) { return }

    Write-Host "*************************************************************************************************************"
    Write-Host -Foreground Yellow "The next step is a manual step"
    Write-Host "You will need to create any role centres. Please refer to the deployment notes on how to do this"
    Write-Host
    Read-Host -Prompt "Press enter to continue"
}

function Deploy-AifPorts
{
    if($RunHeadless.IsPresent) { return }

    Write-Host "*************************************************************************************************************"
    Write-Host "The next step is another manual step"
    Write-Host "You need to deploy any new AIF ports.  Please refer to the deployment notes on how to do this"
    Write-Host
    Read-Host -Prompt "Press enter to continue"
}

function Publish-Cubes
{
    if($RunHeadless.IsPresent) { return }

    Write-Host "*************************************************************************************************************"
    Write-Host "The next step is another manual step"
    Write-Host "You need to redeploy the SQL cubes.  Please refer to the deployment notes on how to do this"
    Write-Host
    Read-Host -Prompt "Press enter to continue"
}


###################################################################
# Execution starts here!
###################################################################
# Variables to help us handle auto-rollback on deployment failure
$hasSchemaCreated = $false
$hasSchemaApplied = $false
$hasSyncronised = $false

# Grab the deployment file version
$deploymentModelStoreFile = Get-LatestModelStore

# variables to hold the deployment and backup schema names 
# NOTE WELL: AX Schema names can't have spaces, underscores, and hyphens ... and perhaps others.
$datestamp = Get-Date -Format "yyyyMMddhhmm"
$backupSchema = "Backup${datestamp}"
$schema = "Deployment${datestamp}" 

# Configuration options
$config = $environments[$Target.ToUpperInvariant()]
$aosInstances = $config.aosServers
$dbServer = $config.databaseServer
$aosUser = $config.aosServiceUser
$reportingServers = $config.reportingServers
$enterpriseUrl = $config.enterprisePortalUrl

$configurationFile = [System.IO.Path]::Combine($scriptDirectory, "Config", $config.configuration)
$modelStoreFile = [System.IO.Path]::Combine($scriptDirectory, $deploymentModelStoreFile)

Write-Host "*************************************************************************"
Write-Host " AX ModelStore Deployment to $Target"
Write-Host "*************************************************************************"
Write-Host -ForegroundColor Yellow "Warning: This is a semi-manual process!!"
Write-Host "You will be prompted to perform actions within AX itself."
Write-Host "Please ensure you have administrator access before continuing."
Write-Host 

Abort-IfUnmetDependencies


Write-Host "************************************************************************"
Write-Host "Deployment Settings"
Write-Host "************************************************************************"
Write-Host "Target                : $target"
Write-Host
Write-Host "Model Store File      : $deploymentModelStoreFile"
Write-Host "AoS instances         : $aosInstances"
Write-Host "Aos Service User      : $aosUser"
Write-Host "Database Server       : $dbServer"
Write-Host "Reporting Servers     : $reportingServers"
Write-Host "Enterprise Portal Url : $enterpriseUrl"
Write-Host "Client Config File    : $configurationFile"
Write-Host "************************************************************************"


if($RunHeadless.IsPresent -eq $false)
{
    Write-Host "Do you wish to continue? [Y/N]"
    $continue = Read-Host

    if($continue.ToUpperInvariant() -ne "Y") { exit } 
}

Reject-NewAxClients

# Only restart reporting services / ping enterprise portal if they're used.
if($config["reportingServers"].Count -gt 0)
{
    Restart-ReportingServers -servers $config["reportingServers"]
}

if($config["enterprisePortalServers"].Count -gt 0)
{
    recycleEnterpriseServers -servers $config["enterprisePortalServers"]
}

try
{
    $ErrorActionPreference = "Stop"

    Write-Host "Creating temporary schema '$schema' to hold this deployment"
    Initialize-AXModelStore -AOSAccount $aosUser -SchemaName $schema -Server $dbServer -Database $modelDatabaseName -NoPrompt

    Write-Host "Importing new model store into temporary schema"
    Import-AxModelStore -Server $dbServer -Database $modelDatabaseName -SchemaName $schema -File "$scriptDirectory\$deploymentModelStoreFile"  -NoPrompt
    $hasSchemaCreated = $true;

    Write-AosShutdownImminentWarning
    Stop-AoSInstances -servers $aosInstances

    Write-Host "Applying new schema"
    Import-AxModelStore -Server $dbServer -Database $modelDatabaseName -Apply "$schema" -BackupSchema "$backupSchema" -NoPrompt
    $hasSchemaApplied = $true

    # Start first instance so we can perform a database sync
    Write-Host "Starting single AOS instance to perform database synchronisation"    
    [string[]] $firstServer = @($aosInstances[0]);
    Start-AosInstances -servers $firstServer

    Invoke-DatabaseSynchronisation -ClientConfigFile $configurationFile -timeout 60
    $hasSyncronised = $true

    Write-Host "Publishing reports"
    # This usually error due to dev errors in the reports. Needs removal when fixed.
    $ErrorActionPreference = "Continue"
    # Publish-AllAxReports -ConfigurationFile  $configurationFile
    $ErrorActionPreference = "Stop"

    Create-RoleCentres
    Publish-Cubes
    Deploy-EnterprisePortalUpdates -url $enterpriseUrl
    Deploy-AifPorts

    Write-Host "Cleaning up post-deploy"
    CleanupMetaData -Server $dbServer -Database $modelDatabaseName -aosServiceUser $aosUser -tempSchema $schema -backupSchema $backupSchema

    Write-Host "Starting all AoS instances"
    Start-AosInstances -servers $aosInstances

    # Accept clients
    Accept-NewAxClients
}
catch
{
    Write-Host "Deploy failed with message '$_'"  
    Write-Host "Rolling back deployment"

    if($hasSchemaApplied)
    {
        Import-AxModelStore -Server $dbServer -Database $modelDatabaseName -Apply "$backupSchema" -NoPrompt
        Initialize-AXModelStore -AOSAccount $aosUser -Drop $backupSchema -Server $dbServer -Database $modelDatabaseName -NoPrompt
    }

    if($hasSchemaCreated)
    {
        Initialize-AXModelStore -AOSAccount $aosUser -Drop $schema -Server $dbServer -Database $modelDatabaseName -NoPrompt
    }
    
    if($hasSyncronised)
    {
        Write-Host "Re-running db sync to revert db changes"
        Invoke-DatabaseSynchronisation -ClientConfigFile $configurationFile -timeout 60
    }
}