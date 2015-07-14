###################################################################################
# Utility methods
###################################################################################
function Test-ServiceIsRunning
{
    Param (
        $Name = $(throw "Please supply the service name to test")
    );

    if((Get-Service -Name $Name | Select -ExpandProperty "Status") -eq "Running") 
    {
        return $true
    }
    return $false
}

function FormatBuildEvent
{
    Param(
        [string] $source = $(throw "Please supply the source of the log event"), 
        [string] $level = $(throw "Please supply the log level"), 
        [string] $message = $(throw "Please supply the log message")
    );

    Write-Host "($source) [$level]: $message"
}

function Parse-AxBuildLogFile
{
    Param(    
        [string] $AXBuildLog = $(throw "axbuild logfile is a required parameter")
    );
        
    $progname = [System.Io.Path]::Combine($env:BUILD_SOURCESDIRECTORY, "BuildTools", "CompilationLogParser", "CompilationLogParser.exe")
            
    & $progname $AxBuildLog
    
    if($LASTEXITCODE -ne 0) 
    {
         throw "An error occurred whilst processing the axbuild log. Stopping build"
    }       
}

function Invoke-AxBuild
{    
    Param(    
        [string] $ClientBinDir = $(throw "Client Bin Directory is a required parameter"),  
        [string] $ServerBinDir = $(throw "Server Bin Directory is a required parameter"),
        [string] $AosInstanceId = $(throw "Aos Instance Id is a required parameter"), 
        [string] $DatabaseServer = $(throw "Database Server Name is a required parameter"), 
        [string] $ModelDatabase = $(throw "Model database name is a required parameter"), 
        [string] $AXBuildLogPath = $(throw "axbuild logfile path is a required parameter"), 
        [string] $DropDir = $(throw "Drop Directory is a required parameter"),
        [bool] $CopyLogFile = $true,
        [int] $axBuildWorkerCount=8, 
        [int] $timeoutInMinutes=0
    );

    $timeTaken = Measure-Command {

        $compile = New-Object CodeCrib.AX.AXBuild.Commands.Compile
        $compile.AltBinDir = $ClientBinDir
        $compile.AOSInstance = $AosInstanceId
        $compile.DbServer = $DatabaseServer
        $compile.DbName = $ModelDatabase
        $compile.LogPath = $AXBuildLogPath
        $compile.Workers = $axBuildWorkerCount
        $compile.Compiler = [System.IO.Path]::Combine($ServerBinDir, "Ax32Serv.exe")

        # Wait for process and kill if it times out
        [System.Diagnostics.Process] $process = [CodeCrib.AX.AXBuild.AXBuild]::StartCommand($ServerBinDir, $compile);

        # Special wait section as it has to also kill children...
        if ($process.Id -gt 0)
        {               
            if($timeoutMinutes -gt 0)
            {
                $timespan = New-Object TimeSpan -ArgumentList @(0, $timeoutInMinutes, 0)

                if(-Not ($process.WaitForExit($timespan.TotalMilliseconds)))
                {
                    # Process didn't exit within time limit
                    Try 
                    {
                        $process.Kill()
                        # Kill child processes, too.
                        $mos = New-Object System.Management.ManagementObjectSearcher -ArgumentList @(, "SELECT ProcessId, Name FROM Win32_Process WHERE ParentProcessId = ${process.Id}")

                        foreach($obj in $mos.Get())
                        {
                            $processName = $obj.Properties["Name"].Value;
                            if($processName -eq "Ax32Serv.exe")
                            {
                                $processId = [int] $obj.Properties["ProcessId"].Value;

                                if($processId -gt 0)
                                {
                                    $subProcess = [System.Diagnostics.Process]::GetProcessById($processId)

                                    if(!$subProcess.HasExited)
                                    {
                                        $subProcess.Kill();
                                    }
                                }
                            }
                        }

                        $mos.Dispose();
                        throw "Client time out of $timeoutMinutes minutes exceeded";
                    }
                    Catch
                    {
                        throw "Client time out of $timeoutMinutes minutes exceeded, and also encountered an exception whilst trying to kill the running process";
                    }
                }
            }
            else
            {
                $process.WaitForExit()
            }
        }
    
        # Grab log output
        $axCompileLog = [System.IO.Path]::Combine($axBuildLogPath, "AxCompileAll.html")

        if($CopyLogFile) 
        {
            Copy-Item -Path $axCompileLog -Destination $DropDir
        }

        Parse-AxBuildLogFile -AXBuildLog "$axCompileLog" | Write-Host 
    }

    FormatBuildEvent -source "AxBuild" -level "Info" -message "Full recompile via AXBuild took ${timeTaken}"
}

function Merge-XPOs
{
    Param(
        [string] $BuildNumber = $(throw "Please supply the current build number"),
        [string] $SourcesDirectory = $(throw "Please supply the directory containing the source"),
        [string] $BinariesDirectory = $(throw "Please supply the directory containing the binaries"),
        [string] $ModelName = $(throw "Please supply the model name")
    );

    $timeTaken = Measure-Command {
        $combinedFileName = $BuildNumber + ".xpo"
        $xpoDir = [System.IO.Path]::Combine($SourcesDirectory, $ModelName);
        $outputFile = [System.IO.Path]::Combine($BinariesDirectory, $combinedFileName);

        & "C:\Program Files\Microsoft Dynamics AX\60\ManagementUtilities\CombineXPOs.exe"  -XpoDir $xpoDir -CombinedXpoFile $outputFile | Out-Null

        if($LASTEXITCODE -gt 0) {
            throw "An error occured whilst attemping to combine all the XPO files." 
        }
    }

    FormatBuildEvent -source "Merge-XPOs" -level "Info" -message "Merging XPO files took ${timeTaken}"

    return $outputFile
}

function Import-XPO
{  
    Param(
        [string] $XpoFileName = $(throw "Please supply the name of the combined XPO file to import"),
        [string] $modelName = $(throw "Please supply the name of the model to import into"),
        [string] $layer = $(throw "Please supply the layer you wish to import the model into"),
        [string] $publisher,        
        [string] $timeoutInMinutes = 0
        );

    $timeTaken = Measure-Command {

        if(-Not (Test-Path -Path $XpoFileName))
        {
            throw "Unable to read XPO file, aborting build"
        }

        $logFile = generateLogFileForProcess -process "ImportLog"

        $client = New-Object CodeCrib.AX.Client.AutoRun.AxaptaAutoRun
        $client.ExitWhenDone = $true
        $client.LogFile = $logFile

        $step = New-Object CodeCrib.AX.Client.AutoRun.XpoImport
        $step.File = $XpoFileName

        $client.Steps.Add($step)

        $command = New-Object CodeCrib.AX.Client.Commands.AutoRun

        if($clientConfigFile) 
        {
            $command.ConfigurationFile = $configFile
        }

        $autoRunFile = generateAutoRunFile -process "AutoRun-ImportLog" -client $client
    
        $command.Filename = $autoRunFile
        $command.Layer = $layer
        $command.Model = $modelName
        $command.ModelPublisher = $publisher

        $command.Development = $true
        $command.Minimize = $true
        $command.LazyClassLoading = $true
        $command.LazyTableLoading = $true
        $command.NoCompileOnImport = $true
        $command.HideModalDialogs = $true

        $process = [System.Diagnostics.Process] [CodeCrib.AX.Client.Client]::StartCommand($command)
        waitForProcess -processId $process.Id -timeoutMinutes $timeoutInMinutes

        if(Test-Path -Path $logFile)
        {
            $stopTheBuild = $false

            FormatBuildEvent -source "Import-XPO" -level "Info" -message "Log file output------------------------------------------------------------------"
            [xml] $xml = Get-Content $logFile
            foreach($infoMsg in $xml.AxaptaAutoRun.XpoImport.Info)
            {
                FormatBuildEvent -source "Import-XPO" -level "Info" -message $infoMsg

                if($infoMsg.EndsWith("errors"))
                {
                    $errorCount = [int] $infoMsg.Replace(" errors", "")
                    if($errorCount -gt 0) 
                    {
                        $stopTheBuild = $true
                    }
                }
            }
            
            if($stopTheBuild)
            {
                throw "Import errors stopped the build from continuing. Please fix these and try again!"
            }
            FormatBuildEvent -source "Import-XPO" -level "Info" -message "Log file output------------------------------------------------------------------"
        }

        Remove-Item $autoRunFile
    }
    FormatBuildEvent -source "Import-XPO" -level "Info" -message "Importing Xpp code took ${timeTaken}"
}

function Invoke-CILGeneration
{
    Param(
        [string] $ClientConfigFile,
        [int] $timeoutInMinutes = 0
        );

    $timeTaken = Measure-Command {

        $logFile = generateLogFileForProcess -clientConfigFile $ClientConfigFile -process "CompileILLog"


        $command = New-Object CodeCrib.AX.Client.Commands.GenerateCIL
    
        if($ClientConfigFile) {
            $command.ConfigurationFile = $ClientConfigFile
        }       

        $client = New-Object CodeCrib.AX.Client.AutoRun.AxaptaAutoRun
        $client.ExitWhenDone = $true
        $client.LogFile = $logFile

        $command = New-Object CodeCrib.AX.Client.AutoRun.CompileIL 
        $command.Incremental = $false
        $client.Steps.Add($command)

        $autoRunFile = generateAutoRunFile -process "CompileIL" -client $client

        $autoRunObject = New-Object CodeCrib.AX.Client.Commands.AutoRun
        if($clientConfigFile) 
        {
            $autoRunObject.ConfigurationFile = $clientConfigFile
        }

        $autoRunObject.Filename = $autoRunFile
        $autoRunObject.Minimize = $true
        $autoRunObject.Development = $true        
        $autoRunObject.LazyClassLoading = $true
        $autoRunObject.LazyTableLoading = $true
        $autoRunObject.NoCompileOnImport = $true
        $autoRunObject.HideModalDialogs = $true

        [System.Diagnostics.Process] $process = [CodeCrib.AX.Client.Client]::StartCommand($autoRunObject)

        waitForProcess -processId $process.Id -timeoutMinutes $timeoutInMinutes

        if(Test-Path -Path "$logFile")
        {
            FormatBuildEvent -source "Invoke-CILGeneration" -level "Info" -message "Log file output------------------------------------------------------------------"

            $content = Get-Content "$logFile"
            $stopBuild = $false

            foreach($line in $content)
            {
                FormatBuildEvent -source "Invoke-CILGeneration" -level "Info" -message $line

                if($line.StartsWith("Errors"))
                {
                    $intCount = [int] $line.SubString(8)

                    if($intCount -gt 0) 
                    {
                        $stopBuild = $true
                    }                    
                }
            }
            
            FormatBuildEvent -source "Invoke-CILGeneration" -level "info" -message "Log file output------------------------------------------------------------------"

            if($stopBuild) 
            {
                throw "Build errors stopped the build. Please fix them and re-build"
            }
        }
    }

    FormatBuildEvent -source "Invoke-CILGeneration" -level "info" -message "Generating CIL took ${timeTaken}"
}

function Invoke-DatabaseSynchronisation
{
    Param(
        [string] $ClientConfigFile,
        [int] $timeoutInMinutes = 0
    );

    $timeTaken = Measure-Command {
        $logFile = generateLogFileForProcess -clientConfigFile $ClientConfigFile -process "SynchronizeLog"

        $client = New-Object CodeCrib.AX.Client.AutoRun.AxaptaAutoRun
        $client.ExitWhenDone = $true
        $client.LogFile = $logFile

        $command = New-Object CodeCrib.AX.Client.AutoRun.Synchronize 
        $command.SyncDB = $true
        $command.SyncRoles = $true
        $client.Steps.Add($command) 
        $autoRunFile = generateAutoRunFile -process "Synchronize" -client $client

        $autoRunObject = New-Object CodeCrib.AX.Client.Commands.AutoRun
        if($clientConfigFile) 
        {
            $autoRunObject.ConfigurationFile = $clientConfigFile
        }

        $autoRunObject.Filename = $autoRunFile
        $autoRunObject.Minimize = $true
        $autoRunObject.Development = $true
        
        $autoRunObject.LazyClassLoading = $true
        $autoRunObject.LazyTableLoading = $true
        $autoRunObject.NoCompileOnImport = $true
        $autoRunObject.HideModalDialogs = $true

        [System.Diagnostics.Process] $process = [CodeCrib.AX.Client.Client]::StartCommand($autoRunObject)

        waitForProcess -processId $process.Id -timeoutMinutes $timeoutInMinutes

        if(Test-Path -Path $logFile) 
        {
            FormatBuildEvent -source "Invoke-DatabaseSynchronisation" -level "info" -message "Log file output------------------------------------------------------------------"

            [xml] $xml = Get-Content "$logFile"
            foreach($line in $xml.AxaptaAutoRun.Infolog)
            {
                FormatBuildEvent -source "Invoke-DatabaseSynchronisation" -level "info" -message $line
            }
            
            FormatBuildEvent -source "Invoke-DatabaseSynchronisation" -level "info" -message "Log file output------------------------------------------------------------------"
        }

        Remove-Item $autoRunFile
    }

    FormatBuildEvent -source "Invoke-DatabaseSynchronisation" -level "info" -message "database synchronisation took ${timeTaken}"
}

function removeCachedItems([string] $path, [string] $filePattern) 
{
    $files = [System.IO.Directory]::EnumerateFiles($path, $filePattern)
    foreach($file in $files) 
    {
        [System.IO.File]::SetAttributes($file, [System.IO.FileAttributes]::Normal)
        [System.IO.File]::Delete($file);
    }
}

function removeCachedItemsRecursive([string] $path, [string] $pathPattern, [string] $filePattern) 
{
    if(Test-Path -Path $path) 
    {
        $folders = [System.IO.Directory]::EnumerateDirectories($path, $pathPattern)
        foreach($folder in $folders)
        {
            removeCachedItems -path $folder -filePattern $filePattern
        }
    }
}

function Clear-AXCacheFolders
{
    Param(
        [string] $serverBinDir = $(throw "Please supply the server bin directory location")
        )

    FormatBuildEvent -source "Clear-AXCacheFolders" -level "info" -message "Cleaning server label artifacts"
    $dir = [System.IO.Path]::Combine($serverBinDir, "Application\Appl\Standard") 
    removeCachedItems -path "$dir" -filePattern "ax*.al?"

    FormatBuildEvent -source "Clear-AXCacheFolders" -level "info" -message "Cleaning server XppIL artifacts"
    $dir = [System.IO.Path]::Combine($serverBinDir, "XppIL") 
    removeCachedItems -path "$dir" -filePattern "*"

    FormatBuildEvent -source "Clear-AXCacheFolders" -level "info" -message "Cleaning server VSAssemblies artifacts"
    $dir = [System.IO.Path]::Combine($serverBinDir, "VSAssemblies") 
    removeCachedItems -path "$dir" -filePattern "*"

    FormatBuildEvent -source "Clear-AXCacheFolders" -level "info" -message "Cleaning client cache artifacts"
    removeCachedItems -path "$env:LOCALAPPDATA" -filePattern "ax_*.auc"
    removeCachedItems -path "$env:LOCALAPPDATA" -filePattern "ax*.kti"
    
    FormatBuildEvent -source "Clear-AXCacheFolders" -level "info" -message "Cleaning client VSAssemblies artifacts"
    $dir = [System.IO.Path]::Combine($env:LOCALAPPDATA, "Microsoft\Dynamics Ax") 
    removeCachedItemsRecursive -path "$dir"  -pathPattern "VSAssemblies*" -filePattern "*"     
}

function generateAutoRunFile
{
    Param(
        [string] $process = $(throw "Please supply the name of the calling process"), 
        [CodeCrib.AX.Client.AutoRun.AxaptaAutoRun] $client = $(throw "Please supply the AxaptaAutRun client")
    );

    $autoRunFile = [System.IO.Path]::Combine($env:TEMP, ($process + "-" + [Guid]::NewGuid() + ".xml"))
    [CodeCrib.AX.Client.AutoRun.AxaptaAutoRun]::SerializeAutoRun($client, $autoRunFile)

    return $autoRunFile
}

function generateLogFileForProcess
{
    Param(
        [string] $clientConfigFile,
        [string] $process = $(throw "Please supply the name of the calling process")
    );

    if(-Not $clientConfigFile)
    {
        $config = Get-ClientConfiguration -active
    } 
    else 
    {
        $config = Get-ClientConfiguration -filename $clientConfigFile
    }

    $filename = $process + "-" + [Guid]::NewGuid() + ".xml" 
    $logDir = $config.LogDirectory;

    if($isAutomatedBuild) {
        # Place in drop directory.
        $logDir = $binariesDirectory;
    }
    
    if($logDir.StartsWith("%USERPROFILE%"))
    {
        # Pesky env vars. Lets substitute them
        $logDir = [System.Environment]::ExpandEnvironmentVariables($logDir)
    }

    return [System.IO.Path]::Combine($logDir, $filename)
}

function isLabelFileEmpty
{
    Param([string] $labelFile = $(throw "Please supply the name of the label file to check"));

    if(Test-Path -Path $labelFile)
    {
        $reader = New-Object System.IO.StreamReader -ArgumentList @(, [System.IO.File]::OpenRead($labelFile))
        $isEmptyFile = $true
        $lineCounter = 0

        while($isEmptyFile -and !$reader.EndOfStream -and $lineCounter -lt 50) 
        {
            $line = $reader.ReadLine().Trim()

            if($line -match "@.{3}\d+\s.+")
            {
                $isEmptyFile = $false
            }
        }

        $reader.Dispose()
    }

    return $isEmptyFile
}

function waitForProcess
{
    Param(
        [int] $processId = $(throw "Please supply a process id to wait on exiting"),
        [int] $timeoutMinutes=0
    );

    if ($processId -gt 0)
    {
        $process = [System.Diagnostics.Process]::GetProcessById($processId)
                
        if($timeoutMinutes -gt 0)
        {
            $timespan = New-Object TimeSpan -ArgumentList @(0, $timeoutMinutes, 0)

            if(-Not ($process.WaitForExit($timespan.TotalMilliseconds)))
            {
                # Process didn't exit within time limit

                Try 
                {
                    $process.Kill()
                    throw "Client time out of $timeoutMinutes minutes exceeded";
                }
                Catch
                {
                    throw "Client time out of $timeoutMinutes minutes exceeded, and also encountered an exception whilst trying to kill the running process";
                }
            }
        }
        else
        {
            $process.WaitForExit()
        }
    }
}

function Import-Labels
{
    Param(
        [string] $sourcesDirectory = $(throw "Please supply the sources directory"),
        [string] $modelName = $(throw "Please supply the model name"),
        [string] $clientConfigFile,
        [string] $layer = $(throw "Please supply the name of the target layer"),
        [string] $publisher,
        [int] $timeoutInMinutes = 10
        );

    $timeTaken = Measure-Command {
        # Check to see if label dir exists
        $labelDir = [System.IO.Path]::Combine($sourcesDirectory, $modelName, "label files")

        if(-Not (Test-Path -Path "$labelDir"))
        {
            FormatBuildEvent -source "Import-Labels" -level "Warning" -message "Label file folder '$labelDir' was not found, skipping import."
            return;
        } 
 
        # Generate log file
        $logFile = generateLogFileForProcess -clientConfigFile $clientConfigFile -process "AutoRun-LabelFlush"

        # Set up a client for running a series of label flushes
        $autoRunClient = New-Object CodeCrib.AX.Client.AutoRun.AxaptaAutoRun
        $autoRunClient.ExitWhenDone = $true
        $autoRunClient.LogFile = $logFile

        # Set up a command for running label imports
        $command = New-Object CodeCrib.AX.Client.Commands.ImportLabelFile
        if($clientConfigFile) {
            $command.ConfigurationFile = $clientConfigFile
        }
        $command.Layer = $layer
        $command.Model = $modelName
        $command.ModelPublisher = $publisher

        $command.Development = $true
        $command.Minimize = $true
        $command.LazyClassLoading = $true
        $command.LazyTableLoading = $true
        $command.NoCompileOnImport = $true
        $command.HideModalDialogs = $true

        foreach($label in [System.IO.Directory]::GetFiles($labelDir, "*.ald")) 
        {
            FormatBuildEvent -source "Import-Labels" -level "Info" -message "Importing label file '$label'"
                
            if(-not (isLabelFileEmpty -labelFile $label)) 
            {
                # import a given label
                $command.Filename = $label
                [CodeCrib.AX.Client.Client]::ExecuteCommand($command, $timeoutInMinutes)
            
                # Set up a task to flush the label
                $labelFile = [System.IO.Path]::GetFileNameWithoutExtension($label).Substring(2, 3)
                $labelLanguage  = [System.IO.Path]::GetFileNameWithoutExtension($label).Substring(5)

                $autoRun = New-Object CodeCrib.AX.Client.AutoRun.Run
                $autoRun.Type = [CodeCrib.AX.Client.AutoRun.RunType]::class
                $autoRun.Name = "Global"
                $autoRun.Method = "info"
                $autoRun.Parameters = "strFmt(`"Flush label $labelFile language ${labelLanguage}: %1`", Label::flush(`"$labelFile`",`"$labelLanguage`"))"

                $autoRunClient.Steps.Add($autoRun)
            }
        }

        $autoRunFile = generateAutoRunFile -process "AutoRun-LabelFlush" -client $autoRunClient

        # flush all label files changed
        $autoRunObject = New-Object CodeCrib.AX.Client.Commands.AutoRun
        if($clientConfigFile) 
        {
            $autoRunObject.ConfigurationFile = $clientConfigFile
        }
        $autoRunObject.Layer = $layer
        $autoRunObject.Model = $modelName
        $autoRunObject.ModelPublisher = $publisher
        $autoRunObject.Filename = $autoRunFile
        $autoRunObject.Minimize = $true
        $autoRunObject.Development = $true
        $autoRunObject.LazyClassLoading = $true
        $autoRunObject.LazyTableLoading = $true
        $autoRunObject.NoCompileOnImport = $true
        $autoRunObject.HideModalDialogs = $true

        $process = [System.Diagnostics.Process] [CodeCrib.AX.Client.Client]::StartCommand($autoRunObject)
        $axProcessId = $process.Id
        
        waitForProcess -processId $axProcessId -timeoutMinutes $timeoutInMinutes

        if(Test-Path -Path $logFile)
        {
            FormatBuildEvent -source "Import-Labels" -level "Info" -message "Log file output------------------------------------------------------------------"

            [xml] $xml = Get-Content $logFile

            foreach($line in $xml.AxaptaAutoRun.LabelFlush.Info)
            {
                FormatBuildEvent -source "Import-Labels" -level "Info" -message  $line
            }
            FormatBuildEvent -source "Import-Labels" -level "Info" -message "Log file output------------------------------------------------------------------"
        }

        Remove-Item $autoRunFile
    }

    FormatBuildEvent -source "Import-Labels" -level "Info" -message "importing labels took ${timeTaken}"
}

function Import-VisualStudioProjects
{
    Param(
        [string] $sourcesDirectory = $(throw "Please supply the sources directory"),
        [string] $modelName = $(throw "Please supply the model name"),
        [string] $clientConfigFile,
        [string] $layer = $(throw "Please supply the name of the target layer"),
        [string] $publisher,
        [int] $timeoutInMinutes = 10
    );

    $timeTaken = Measure-Command {

        $projectsDir = [System.IO.Path]::Combine($sourcesDirectory, $modelName, "Visual Studio Projects")

        if(-Not (Test-Path -Path "$projectsDir"))
        {
            FormatBuildEvent -source "Import-VisualStudioProjects" -level "Warning" -message "The Visual Studio Projects folder ('$projectsDir') was not found."
            return;
        } 
 
        # Generate log file
        $logFile = generateLogFileForProcess -clientConfigFile $clientConfigFile -process "VSImportLog"

        # Set up a client for running a series of label flushes
        $autoRunClient = New-Object CodeCrib.AX.Client.AutoRun.AxaptaAutoRun
        $autoRunClient.ExitWhenDone = $true
        $autoRunClient.LogFile = $logFile
    
        $projects = [System.IO.Directory]::GetFiles($projectsDir, "*.csproj", [System.IO.SearchOption]::AllDirectories);
        $projects += [System.IO.Directory]::GetFiles($projectsDir, "*.dynamicsproj", [System.IO.SearchOption]::AllDirectories);
        $projects += [System.IO.Directory]::GetFiles($projectsDir, "*.vbproj", [System.IO.SearchOption]::AllDirectories);

        foreach($project in $projects)
        {
            $autoRun = New-Object CodeCrib.AX.Client.AutoRun.Run
            $autoRun.Type = [CodeCrib.AX.Client.AutoRun.RunType]::class
            $autoRun.Name = "SysTreeNodeVSProject"
            $autoRun.Method = "importProject"
            $autoRun.Parameters = "@'"+ $project + "'"

            $autoRunClient.Steps.Add($autorun);
        }

        $autoRunFile = generateAutoRunFile -process "AutoRun-VSImport" -client $autoRunClient

        $autoRunObject = New-Object CodeCrib.AX.Client.Commands.AutoRun
        if($clientConfigFile) 
        {
            $autoRunObject.ConfigurationFile = $clientConfigFile
        }
        $autoRunObject.Layer = $layer
        $autoRunObject.Model = $modelName
        $autoRunObject.ModelPublisher = $publisher
        $autoRunObject.Filename = $autoRunFile
        $autoRunObject.Minimize = $true
        $autoRunObject.Development = $true
        $autoRunObject.LazyClassLoading = $true
        $autoRunObject.LazyTableLoading = $true
        $autoRunObject.NoCompileOnImport = $true
        $autoRunObject.HideModalDialogs = $true
        
        $process = [System.Diagnostics.Process] [CodeCrib.AX.Client.Client]::StartCommand($autoRunObject)

        waitForProcess -processId $process.Id -timeoutMinutes $timeoutInMinutes

        if(Test-Path -Path $logFile)
        {
            FormatBuildEvent -source "Import-VisualStudioProjects" -level "Info" -message "Log file output------------------------------------------------------------------"
            [xml] $xml = Get-Content $logFile
            foreach($line in $xml.AxaptaAutoRun.Info)
            {
                FormatBuildEvent -source "Import-VisualStudioProjects" -level "Info" -message $line
            }
            FormatBuildEvent -source "Import-VisualStudioProjects" -level "Info" -message "Log file output------------------------------------------------------------------"
        }

        Remove-Item $autoRunFile
    }

    FormatBuildEvent -source "Import-VisualStudioProjects" -level "Info" -message "importing visual studio projects took ${timeTaken}"
}

function Publish-AllAxReports
{
	Param( [string] $ConfigurationFile )

    $timeTaken = Measure-Command {

		# TODO: This currently fails on every publish, due to reports with errors in them.
		# This will allow us to continue and produce builds (for now).
		# We need to investigate the cause of this, and once we fix that,  we can remove the change to 
        # the ErrorActionPreference level
		$ErrorActionPreference = "Continue"

        if($clientConfigFile)  
        {
            Publish-AXReport -ServicesFilePath "$ConfigurationFile" -ReportName *
        } 
        else 
        {
            Publish-AXReport -ReportName * 
        }

		$ErrorActionPreference = "Stop"
    }

    FormatBuildEvent -source "Publish-AllAxReports" -level "Info" -message "Publishing all reports took ${timeTaken}"
}

$exportedFunctions = "Invoke-AxBuild", "Merge-XPOs", "Import-XPO", "Invoke-CILGeneration", "Invoke-DatabaseSynchronisation", "Clear-AXCacheFolders", "Import-Labels", "Import-VisualStudioProjects", "Publish-AllAxReports", "FormatBuildEvent", "Test-ServiceIsRunning"

Export-ModuleMember -Function $exportedFunctions