@echo off
ver | find "6.0" > nul
if %ERRORLEVEL% == 0 goto detect2008

ver | find "6.1" > nul
if %ERRORLEVEL% == 0 goto ver_2008R2

ver | find "6.2" > nul
if %ERRORLEVEL% == 0 goto ver_2012

if not exist %SystemRoot%\system32\systeminfo.exe goto failed

:detect2008
if exist "%ProgramFiles(x86)%" goto ver_2008x64
else goto ver_2008x86

:ver_2008x86
echo Windows Server 2008 x86 Detected
echo Copying: Cleanmgr.exe
COPY C:\Windows\winsxs\x86_microsoft-windows-cleanmgr.resources_31bf3856ad364e35_6.0.6001.18000_en-us_5dd66fed98a6c5bc\cleanmgr.exe.mui %systemroot%\System32\en-US\Cleanmgr.exe.mui
echo Copying: Cleanmgr.exe.mui
COPY C:\Windows\winsxs\x86_microsoft-windows-cleanmgr_31bf3856ad364e35_6.0.6001.18000_none_6d4436615d8bd133\cleanmgr.exe %systemroot%\System32\cleanmgr.exe
goto shortcut

:ver_2008x64
echo Windows Server 2008 x64 Detected
echo Copying: Cleanmgr.exe
COPY C:\Windows\winsxs\amd64_microsoft-windows-cleanmgr.resources_31bf3856ad364e35_6.0.6001.18000_en-us_b9f50b71510436f2\cleanmgr.exe.mui %systemroot%\System32\en-US\cleanmgr.exe.mui
echo Copying: Cleanmgr.exe.mui
COPY C:\Windows\winsxs\amd64_microsoft-windows-cleanmgr_31bf3856ad364e35_6.0.6001.18000_none_c962d1e515e94269\cleanmgr.exe %systemroot%\System32\cleanmgr.exe
goto shortcut

:ver_2008R2
echo Windows 2008R2 Detected
echo Copying: Cleanmgr.exe
COPY C:\Windows\winsxs\amd64_microsoft-windows-cleanmgr.resources_31bf3856ad364e35_6.1.7600.16385_en-us_b9cb6194b257cc63\cleanmgr.exe.mui %systemroot%\System32\en-US\cleanmgr.exe.mui
echo Copying: Cleanmgr.exe.mui
COPY C:\Windows\winsxs\amd64_microsoft-windows-cleanmgr_31bf3856ad364e35_6.1.7600.16385_none_c9392808773cd7da\cleanmgr.exe %systemroot%\System32\cleanmgr.exe
goto shortcut

:ver_2012
echo Windows 2012 Detected
echo Copying: Cleanmgr.exe
COPY      C:\Windows\WinSxS\x86_microsoft-windows-cleanmgr.resources_31bf3856ad364e35_6.2.9200.16384_en-us_b6a01752226afbb3\cleanmgr.exe.mui %systemroot%\System32\en-US\cleanmgr.exe.mui
echo Copying: Cleanmgr.exe.mui
COPY C:\Windows\winsxs\amd64_microsoft-windows-cleanmgr_31bf3856ad364e35_6.2.9200.16384_none_c60dddc5e750072a\cleanmgr.exe %systemroot%\System32\cleanmgr.exe
goto shortcut

:failed
echo Windows OS Version not detected.

:shortcut
SET /P ANSWER=Attempt to create start menu shortcut for all users? (Y/N)
if /i {%ANSWER%}=={y} (goto :yesstartmenu)
if /i {%ANSWER%}=={yes} (goto :yesstartmenu)
goto :exit

:yesstartmenu
set location=%~dp0
echo %location%
COPY %location%\DiskCleanup.lnk %ProgramData%\Microsoft\Windows\"Start Menu"\DiskCleanup.lnk
goto :exit

:exit
SET /P ANSWER=Start Disc Cleanup ? (Y/N)
if /i {%ANSWER%}=={y} (goto :yes) 
if /i {%ANSWER%}=={yes} (goto :yes)
exit

:yes
%systemroot%\System32\cleanmgr.exe