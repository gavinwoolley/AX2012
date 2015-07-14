###################################################################################
# SQL Server utility methods
###################################################################################

function Get-LogicalNamesFromBackup
{
    param(
        [Parameter(Mandatory=$true)]
        [string[]] $BackupFiles,
        $ServerInstance="(local)"
    )

    [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.SMO") | Out-Null
    [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.SmoExtended") | Out-Null

    $server = new-object ('Microsoft.SqlServer.Management.Smo.Server') $ServerInstance
    $restore = new-object('Microsoft.SqlServer.Management.Smo.Restore')
    $restore.NoRecovery  = $false
    $restore.FileNumber = 1

    foreach($file in $BackupFiles) {

        if((Test-Path -Path $file) -eq $false) {
            Write-Host "Unable to find file '$file', skipping"
            continue
        }

        $backup = New-Object("Microsoft.SqlServer.Management.Smo.BackupDeviceItem")($file, "File")
        $restore.Devices.Add($backup)
    }

    Try {
        $smoRestoreDetails = $restore.ReadFileList($server)
    } 
    Catch
    {
        $error[0] | fl -force
        throw $_.Exception
    }

    return ($smoRestoreDetails | Select-Object LogicalName, Type)
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

    Write-Host "Fetching logical devices from backup"

    $logicalNames = Get-LogicalNamesFromBackup -BackupFiles $BackupFiles -ServerInstance $ServerInstance

    $sourceData = ($logicalNames | Where-Object  { $_.Type -eq "D" } | Select -First 1).LogicalName
    $sourceLog = ($logicalNames | Where-Object  { $_.Type -eq "L" } | Select -First 1).LogicalName

    Write-Host
    Write-Host "Restoring database ${Database}"


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
        MOVE '$sourceData' TO '$Destination\$Database.mdf',
        MOVE '$sourceLog' TO '$Destination\${Database}_log.ldf'
   GO

   ALTER DATABASE $Database SET RECOVERY SIMPLE
   GO 

   USE [$Database] DBCC SHRINKFILE (N'$sourceLog' , 0, TRUNCATEONLY) WITH NO_INFOMSGS
"@

    Write-Host $restoreQuery
      
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

function Create-BackupsFolder
{
    param(
        [Parameter(Mandatory=$true)]
        $BackupRoot
        )

    $artifactsDirectory = "c:\artifacts"
           
    if((Test-Path -Path "$artifactsDirectory") -eq $false)
    {
        New-Item -ItemType directory -Path "$artifactsDirectory" | Out-Null
        Copy-Item -Path "$BackupRoot" -Destination "$artifactsDirectory"
    }

    return "$artifactsDirectory\Build Server Backups"
}

function Get-BackupFiles 
{
    param(
        [Parameter(Mandatory=$true)]
        $BackupRoot,
        [Parameter(Mandatory=$true)]
        [ValidateSet('transactional','model')]
        $Type = "transactional"
        )

    if($Type.ToLower() -eq "transactional") {
        $backupGlob = "$BackupRoot\trans_*.bak"
    } else {
        $backupGlob += "$BackupRoot\model_*.bak"
    }

    return (Get-ChildItem -Path "$backupGlob").FullName
}

function Uncompress-DatabaseBackup
{
    param(
        [Parameter(Mandatory=$true)]
        $BackupRoot,
        [Parameter(Mandatory=$true)]
        [ValidateSet('transactional','model')]
        $Type = "transactional"        
    )

    $parentDirectory =  Split-Path -parent $PSScriptRoot    
    $sqbConverter = "$parentDirectory\BuildTools\sqb_converter\sqb2mtf.exe"
    $fileGlob = "";
    $destination = "";
   
    if($Type -eq "transactional") {
        $fileGlob = "$BackupRoot\FULL_SQL_AX_DEV1_AX63_CDS_DEV_20*.sqb"
        $destination = "$BackupRoot\trans.bak"
    } else {
        $fileGlob = "$BackupRoot\FULL_SQL_AX_DEV1_AX63_CDS_DEV_model_*.sqb"
        $destination = "$BackupRoot\model.bak"
    }

    $backupFile = (Get-ChildItem -Path "$fileGlob" | Sort-Object LastWriteTime -Descending | Select-Object -First 1).Name  

   
    & "$sqbConverter" "$BackupRoot\$backupFile" "$destination" | Out-Null
    
    if($LastExitCode -ne 0)
    {
        throw "An error occured whilst converting backup file '$backup', aborting"
    }    
} 

$exportedFunctions = "Get-LogicalNamesFromBackup", "Restore-Database", "Create-BackupsFolder", "Get-BackupFiles", "Uncompress-DatabaseBackup"

Export-ModuleMember -Function $exportedFunctions