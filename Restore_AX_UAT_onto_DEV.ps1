
# Restore.ps1
#
# A powershell script for restoring and reconfiguring UAT backups
# to local development instances.
#
# Usage:
# .\restore.ps1
#
################################################################
# Methods
################################################################

function Test-AdministratorPrivileges {
    $identity  = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal( $identity )
    $principal.IsInRole( [System.Security.Principal.WindowsBuiltInRole]::Administrator )
}

function Create-ArtifactsFolder
{
    $artifactsDirectory = "c:\artifacts"
           
    if(Test-Path -Path "$artifactsDirectory")
    {
        Remove-Item -Path "$artifactsDirectory" -Recurse
    }

    if((Test-Path -Path "$artifactsDirectory") -eq $false)
    {
        New-Item -ItemType directory -Path "$artifactsDirectory" | Out-Null
    }

    return "$artifactsDirectory"
}

function Get-LatestBackups 
{
    param(
        [Parameter(Mandatory=$true)]
        [string] $BackupLocation, 
        [Parameter(Mandatory=$true)]
        [hashtable] $Databases        
    )

    $locations = @{};

    foreach($key in $Databases.Keys) {
        $glob = $Databases[$key]
        $locations[$key] = (Get-ChildItem -Path "$BackupLocation\$glob" | Sort-Object LastWriteTime -Descending | Select-Object -First 1).Name
    }    

    return $locations
}

function Convert-SqlBackupPro
{
    Param(
        [Parameter(Mandatory=$true)]
        [string] $SourceBackupFile,
        [Parameter(Mandatory=$true)]
        [string] $DestinationDirectory
    )

    $sqbConverter = "$PSScriptRoot\Build-Tools\sqb_converter\sqb2mtf.exe"

    $destSqlBackup = Split-Path -Leaf $SourceBackupFile
    $convertedName = $destSqlBackup -replace ".sqb$", ".bak"
    $wildcardedName = $destSqlBackup -replace ".sqb$", "*.bak"

    if($destSqlBackup.Contains("model")) {
        $convertedName = "model.bak"
        $wildcardedName = "model*.bak"
    } else {
        $convertedName = "trans.bak"
        $wildcardedName = "trans*.bak"
    }    
   
    Write-Host
    Write-Host "Convert-SqlBackupPro:"
    Write-Host "    SourceBackupFile: $SourceBackupFile"
    Write-Host "    DestinationDirectory: $DestinationDirectory\$convertedName"
    Write-Host
    Write-Host "Converting backup,  this may take some time."
    
    & $sqbConverter "$SourceBackupFile" "$DestinationDirectory\$convertedName" | Out-Null
    
    if($LastExitCode -ne 0)
    {
        throw "An error occured whilst converting backup file '$SourceBackupFile', aborting"
    }   

    Write-Host "Backup converted."

    return (Get-ChildItem -Path "$DestinationDirectory\$wildcardedName" | Select-Object -Property @{Name="Filename";Expression= {"$_"}}).Filename
}


function Get-AxDatabaseFromDatabaseType
{
    Param(
        [Parameter(Mandatory=$true)]
        [ValidateSet("Transactional", "Model")]
        [string] $DatabaseType
    )

    $axModelDatabaseName = "MicrosoftDynamicsAX_model"
    $axTransactionalDatabaseName = "MicrosoftDynamicsAX"

    switch($DatabaseType) {
        "Transactional" { return $axTransactionalDatabaseName }
        "Model" { return $axModelDatabaseName }       
        default { throw "Unrecognised database type" }
    }            
}


function Install-ALFLicensePlugin
{
    Param(
        [Parameter(Mandatory=$true)]
        [string] $AxServerBinPath,
        [Parameter(Mandatory=$true)]
        [string] $AxClientBinPath,
        [Parameter(Mandatory=$true)]
        [string] $DllFileLocation
    )

    if(Test-Path -Path "$AxServerBinPath\DysLibDax.dll") {
        Remove-Item -Path "$AxServerBinPath\DysLibDax.dll"
    }

    if(Test-Path -Path "$AxClientBinPath\DysLibDax.dll") {
        Remove-Item -Path "$AxClientBinPath\DysLibDax.dll"
    }

    Copy-Item -Path "$DllFileLocation\DysLibDax.dll" -Destination "$AxServerBinPath"
    Copy-Item -Path "$DllFileLocation\DysLibDax.dll" -Destination "$AxClientBinPath"
}


function Reconfigure-AxConfiguration
{
    param(
        [Parameter(Mandatory=$true)]
        [string] $ComputerName,
        [Parameter(Mandatory=$true)]
        [string] $SqlServerInstance
    )

    process 
    {  
        # User\Domain and dns domain are easy to get.
        $currentUser = "$env:USERNAME"
        $userWithDomain = "$env:USERDOMAIN\$env:USERNAME"
        $dnsDomain = $env:USERDNSDOMAIN.ToLower()

        # Get SID for current user.
        $objUser = New-Object System.Security.Principal.NTAccount($env:USERDOMAIN, $env:USERNAME)
        $strSID = $objUser.Translate([System.Security.Principal.SecurityIdentifier])
        $currentUserSid = $strSID.Value

        Write-Host
        Write-Host "Updating AX settings...."

        $sqlcmd = "sqlcmd.exe"

        $sql = @"
        DECLARE @CEORoleId int;
        DECLARE @SystemUserRoleId int;
        DECLARE @MaxRecId bigint;
        DECLARE @UserId varchar(8);
        DECLARE @PartitionId bigint;

        -- Get ID of the partition, the CEO role and System User role
        SELECT @PartitionId = RECID  FROM [MicrosoftDynamicsAX].[dbo].[PARTITIONS] WHERE PARTITIONKEY='initial';

        SELECT @CEORoleId=RECID
            FROM [MicrosoftDynamicsAX_model].[dbo].[SECURITYROLE]
            WHERE AOTNAME = 'CompanyChiefExecutiveOfficer';

        SELECT @SystemUserRoleId=RECID 
            FROM [MicrosoftDynamicsAX_model].[dbo].[SECURITYROLE]
            WHERE AOTNAME = 'SystemUser';

        -- Create user if it doesn't exist
        SELECT @MaxRecId=MAX(RECID)+1 FROM [MicrosoftDynamicsAX].dbo.USERINFO;
        SELECT @UserId = '$' + SUBSTRING(CAST(NEWID() as varchar(64)), 10, 4);

        IF NOT EXISTS(SELECT ID FROM [MicrosoftDynamicsAX].dbo.USERINFO WHERE NAME = '$userWithDomain')
        BEGIN
     
            INSERT INTO [MicrosoftDynamicsAX].dbo.USERINFO(
                ID, NAME, [ENABLE], STATUSLINEINFO, TOOLBARINFO, DEBUGINFO, AUTOINFO, AUTOUPDATE,
                GARBAGECOLLECTLIMIT, HISTORYLIMIT, MESSAGELIMIT, GENERALINFO, SHOWSTATUSLINE, SHOWTOOLBAR, DEBUGGERPOPUP, SHOWAOTLAYER, 
                CONFIRMDELETE, CONFIRMUPDATE, REPORTFONTSIZE, FORMFONTSIZE, PROPERTYFONTSIZE, INFOLOGLEVEL, COMPANY, AUTOLOGOFF, QUERYTIMELIMIT, TRACEINFO, 
                [SID], NETWORKDOMAIN, NETWORKALIAS, ENABLEDONCE, EXTERNALUSER, [LANGUAGE], 
                PREFERREDTIMEZONE, PREFERREDCALENDAR, HOMEPAGEREFRESHDURATION, NOTIFYTIMEZONEMISMATCH, 
                FILTERBYGRIDONBYDEFAULT, GLOBALFORMOPENMODE, SHOWMODELNAMEINAOT, ACCOUNTTYPE, ISSUERRECID, CREDENTIALRECID, 
                GLOBALLISTPAGELINKMODE, GLOBALEXCELEXPORTMODE, GLOBALEXCELEXPORTLOCATION, CLIENTACCESSLOGLEVEL, 
                DEFAULTPARTITION, RECVERSION, [PARTITION], RECID 
            ) VALUES (
                @UserId, 'CONNECT\$currentUser', 1, -13917, -1, 12, -1, 6, 20, 5, 1000,
                -8209, 1, 1, 0, 4, -1, 0, 9, 9, 9, 0, 'CDS', 0, 0, 0,
                '$currentUserSid', '$dnsDomain', '$currentUser', 0, 0, 'EN-GB',
                37, 0, 0, 0, 
                0, 0, 0, 0, 0, 0, 
                0, 0, 0, 0,
                1, 1, @PartitionId, @MaxRecId       
            );
        END
        ELSE
        BEGIN
            SELECT @UserID=ID FROM [MicrosoftDynamicsAX].dbo.USERINFO WHERE NAME = '$userWithDomain'
        END

        SELECT @MaxRecId=MAX(RECID)+1 FROM [MicrosoftDynamicsAX].dbo.SECURITYUSERROLE;

        -- Add CEO role to user if they don't already have it.
        IF NOT EXISTS(SELECT SECURITYROLE FROM [MicrosoftDynamicsAX].[dbo].[SECURITYUSERROLE] WHERE USER_=@UserID AND SECURITYROLE=@CEORoleId)
        BEGIN
            INSERT INTO [MicrosoftDynamicsAX].[dbo].[SECURITYUSERROLE]
                (USER_, SECURITYROLE, ASSIGNMENTSTATUS, ASSIGNMENTMODE, VALIDFROM, VALIDFROMTZID, VALIDTO, VALIDTOTZID, RECVERSION, PARTITION, RECID)
            VALUES
                (@UserId, @CEORoleId, 1, 1, '1900-01-01 00:00:00.000', '0', '1900-01-01 00:00:00.000', '0', 1, @PartitionId, @MaxRecId)

            SET @MaxRecId = @MaxRecId + 1
        END

        -- Add System user role to user if they don't already have it.
        IF NOT EXISTS(SELECT SECURITYROLE FROM [MicrosoftDynamicsAX].[dbo].[SECURITYUSERROLE] WHERE USER_=@UserID AND SECURITYROLE=@SystemUserRoleId)
        BEGIN
            INSERT INTO [MicrosoftDynamicsAX].[dbo].[SECURITYUSERROLE]
                (USER_, SECURITYROLE, ASSIGNMENTSTATUS, ASSIGNMENTMODE, VALIDFROM, VALIDFROMTZID, VALIDTO, VALIDTOTZID, RECVERSION, PARTITION, RECID)
            VALUES
                (@UserId, @SystemUserRoleId, 1, 1, '1900-01-01 00:00:00.000', '0', '1900-01-01 00:00:00.000', '0', 1, @PartitionId, @MaxRecId)

            SET @MaxRecId = @MaxRecId + 1
        END

        -- Reconfigure UAT to local..
        UPDATE [MicrosoftDynamicsAX].[dbo].[SYSGLOBALCONFIGURATION] SET VALUE='http://${ComputerName}:80/DynamicsAX6HelpServer/HelpService.svc' WHERE NAME='HelpServerLocation';
        TRUNCATE TABLE [MicrosoftDynamicsAX].[dbo].[SYSSERVERCONFIG];

        TRUNCATE TABLE [MicrosoftDynamicsAX].[dbo].[SRSSERVERS];
        INSERT INTO [MicrosoftDynamicsAX].[dbo].[SRSSERVERS] (
            SERVERID, ISDEFAULTREPORTMODELSERVER, SERVERURL, ISDEFAULTREPORTLIBRARYSERVER,  AXAPTAREPORTFOLDER, REPORTMANAGERURL,
            SERVERINSTANCE, AOSID, CONFIGURATIONID, ISSHAREPOINTINTEGRATED, RECVERSION, RECID)
        VALUES
        (
            '${ComputerName}',  0, 'http://${ComputerName}/ReportServer_AXDEV', 1, 'DynamicsAx', 'http://${ComputerName}/Reports_AXDEV', 
            'AXDEV', '01@${ComputerName}',  '01@${ComputerName}',  0, 1,  1
        )

        TRUNCATE TABLE  [MicrosoftDynamicsAX].[dbo].[BIANALYSISSERVER];
        INSERT INTO [MicrosoftDynamicsAX].[dbo].[BIANALYSISSERVER] (SERVERNAME, DESCRIPTION, ISVALID, ISDEFAULT, DEFAULTDATABASENAME, PARTITIONS, RECVERSION, RECID)
        VALUES ( '${ComputerName}', 'Dynamics AX analysis server', 1, 1, 'Dynamics AX initial', @PartitionId, 1, 1);

        TRUNCATE TABLE [MicrosoftDynamicsAX].[dbo].[BIANALYSISSERVICESDATABASE];
        INSERT INTO [MicrosoftDynamicsAX].[dbo].[BIANALYSISSERVICESDATABASE] ([ANALYSISSERVICESDATABASENAME],[BIANALYSISSERVER],[ISDEFAULT],[LASTDEPLOYEDDATETIME],[LASTDEPLOYEDDATETIMETZID],[PARTITIONS],[RECVERSION],[RECID])
        VALUES ('Dynamics AX initial', 1,  1, '01-01-1900', 37001,  @PartitionId, 786535868, 5637144576);

        UPDATE [MicrosoftDynamicsAX].[dbo].[SYSEMAILPARAMETERS] SET SMTPRELAYSERVERNAME='localhost' WHERE SMTPRELAYSERVERNAME='ch-exchange.ad.connect-distribution.co.uk'
        DELETE FROM [MicrosoftDynamicsAX].[dbo].[EPWEBSITEPARAMETERS];
"@

        $args = @(
            "-b",
            "-E",
            "-S", "$SqlServerInstance",
            "-Q", "$sql");

        & $sqlcmd $args  | Out-String

        if($LastExitCode -ne 0) {
                throw "An error occurred whilst executing '$sqlcmd'"
        }    
    }
}

function Restore-Database 
{
    Param(
        [Parameter(Mandatory=$true)]
        [string] $ServerInstance,
        [Parameter(Mandatory=$true)]
        [string] $Database,
        [Parameter(Mandatory=$true)]
        [string[]] $BackupFiles,
        [Parameter(Mandatory=$true)]
        [string] $Destination
    )

    Write-Host
    Write-Host "Restoring database ${Database}"


    $moveTarget = "AX63_CDS_UAT"
    if($Database.EndsWith("_model")) {
        $moveTarget+="_model"        
    }

    $sqlcmd = "sqlcmd.exe"

    if($BackupFiles.Length -lt 1) {
        throw "Please specify one (or more) backup files to restore"
    }

    $backupDriveFragments = ""

    foreach($element in $BackupFiles) 
    {
        if($element.Length -gt 259) {
            throw "Backup path element '${element}' is longer than 259 characters, so cannot be restored."
        }

        $backupDriveFragments += "DISK = '$element',"
    }

    $backupDriveFragments = $backupDriveFragments.TrimEnd(",")

    $restoreQuery = @"
    RESTORE DATABASE [$Database] 
        FROM $backupDriveFragments
        WITH FILE = 1,
            NOUNLOAD, 
            REPLACE, 
            STATS = 5,
        MOVE '$moveTarget' TO '$Destination\$Database.mdf',
        MOVE '${moveTarget}_log' TO '$Destination\${Database}_log.ldf'
   GO

   ALTER DATABASE $Database SET RECOVERY SIMPLE
   GO 

   USE [$Database] DBCC SHRINKFILE (N'${moveTarget}_log' , 0, TRUNCATEONLY) WITH NO_INFOMSGS
"@
      
    $args = @(
        "-b",
        "-E",
        "-S", "$ServerInstance",
        "-Q", "$restoreQuery");

    & $sqlcmd $args | Out-String

    if($LastExitCode -ne 0) {
            throw "An error occurred whilst executing '$sqlcmd'"
    }
}

################################################################
# Configuration
################################################################
$backupPath = "\\ax-uat-sql-01\backups$\MSSQL12.SQL_AX_UAT1\MSSQL\Backup"
$SqlServerDataDirectory = "C:\Program Files\Microsoft SQL Server\MSSQL12.AXDEV\MSSQL\DATA"

$databases = @{ 
    Transactional = "FULL_SQL_AX_UAT1_AX63_CDS_UAT_2*.sqb"
    Model = "FULL_SQL_AX_UAT1_AX63_CDS_UAT_model_2*.sqb"    
    };

$axServerInstallPath = "C:\Program Files\Microsoft Dynamics AX\60\Server\MicrosoftDynamicsAX\bin"
$axClientInstallPath = "C:\Program Files (x86)\Microsoft Dynamics AX\60\Client\Bin"
$axBuild = "$axServerInstallPath\AXBuild.exe"

##################################################################
# Main Application
##################################################################
 
If(!(Test-AdministratorPrivileges))
{
    Write-Host -ForegroundColor Red "Please run this script with admin privileges"
    return
}

Push-Location

# Step 1: Create/Recreate artifacts folder.
Write-Host "Creating artifacts folder"
$artifactsDirectory = Create-ArtifactsFolder

# Step 2: Get latest databases
Write-Host "Getting list of latest databases"
[hashtable] $locations = Get-LatestBackups -BackupLocation $backupPath -Databases $databases

$backupFiles = @{};

# Step 3: Convert sql backups#
foreach($key in $locations.Keys) {  
    if($locations[$key] -eq "")
    {
        throw "Unable to locate database backup for {$key} database!, aborting"
    }

    $sourceFilename = $locations[$key]
    
    Write-Host
    Write-Host "Copying backup:"
    Write-Host "        Source: $backupPath\$sourceFilename"
    Write-Host "        Destination:  $artifactsDirectory"
    
    if((Test-Path -Path "$artifactsDirectory\$sourceFilename") -eq $false)
    {
        Copy-Item -Path "$backupPath\$sourceFilename" -Destination "$artifactsDirectory"
    }
     
    $found = Convert-SqlBackupPro -SourceBackupFile "$artifactsDirectory\$sourceFilename" -DestinationDirectory "$artifactsDirectory"
    Remove-Item -Path "$artifactsDirectory\$sourceFilename"
    $backupFiles[$key] = $found   
}

# Step 4: Stop AOS
Stop-Service -Name 'AOS60$01'

# Step 4.5: Blow away XPIL etc..
Write-Host "Clearing XPPIL cache"
if(Test-Path -Path "$axServerInstallPath\XPPIL") {
    Remove-Item -Path "$axServerInstallPath\XPPIL" -Recurse
}

# Step 5: Restore(!)
foreach($key in $backupFiles.Keys) {
    $database = Get-AxDatabaseFromDatabaseType -DatabaseType $key
    $restoreFrom = $backupFiles[$key]

    Restore-Database -ServerInstance "$env:COMPUTERNAME\AXDEV" -Database $database -BackupFiles $restoreFrom  -Destination $SqlServerDataDirectory
}

# Step 6: Deploy / Redeploy dsys license plugin
Write-Host "Installing ALF Licensing plugin"
Install-ALFLicensePlugin -AxServerBinPath $axServerInstallPath -AxClientBinPath $axServerInstallPath -DllFileLocation "$PSScriptRoot\ServiceManagement"

# Step 7: Reconfigure instance.
Write-Host "Reconfiguring AX to use local machine name"
Reconfigure-AxConfiguration -ComputerName $env:COMPUTERNAME -SqlServerInstance "$env:COMPUTERNAME\AXDEV"

# Step 8: Restart AOS
Start-Service -Name 'AOS60$01'

# Step 9: Clean up artifacts folder and we're done!
Remove-Item -Path "$artifactsDirectory/*.bak"
Write-Host "Restore complete!"
Pop-Location