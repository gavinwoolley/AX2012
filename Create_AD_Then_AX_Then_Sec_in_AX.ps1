#Create all AD Groups, AX Users and AX Security Associations

. "C:\Program Files\Microsoft Dynamics AX\60\ManagementUtilities\Microsoft.Dynamics.ManagementUtilities.ps1"
Import-Module ActiveDirectory
$groups = Import-Csv "C:\Users\gwoolley\Desktop\NewAX_Sec_Roles_Export2.csv"
foreach ($group in $groups) {
    $group.name = ($group.name -replace "\/|\+", "")
    New-ADGroup -Name "AX Role - $($group.name)" -Path “OU=AX Roles,OU=Security Groups,OU=Users,OU=Groups,OU=Connect House,DC=ad,DC=connect-distribution,DC=co,DC=uk” -Description "AX Role - $($group.description)" -GroupCategory Security -GroupScope Global -Server AX-DC-01
    New-AXUser -AccountType WindowsGroup -AXUserId $group.ID -UserName "AX Role - $($group.name)" -UserDomain CONNECT -Company CDS
    Add-AXSecurityRoleMember -AOTName $group.AOTName -AxUserID $group.ID
}



write-host Next steps are manual!!!!!!
pause




# Add PROD sysAdmin and PowerUser - Run manually per environment - Check your AOS Server with GET-AXAOS Cmd

    #SysAdmin

    New-ADGroup -Name "AX PROD - SysAdmins" -Path “OU=AX Groups,OU=AX Roles,OU=Security Groups,OU=Users,OU=Groups,OU=Connect House,DC=ad,DC=connect-distribution,DC=co,DC=uk” -Description "AX PROD System Administrators" -GroupCategory Security -GroupScope Global -Server AX-DC-01
    New-AXUser -AccountType WindowsGroup -AXUserId PROADM -UserName "AX PROD - SysAdmins" -UserDomain CONNECT -Company CDS
    Add-AXSecurityRoleMember -AOTName "-SYSADMIN-" -AxUserID PROADM
   
    #Super User

    New-ADGroup -Name "AX PROD - SuperUsers" -Path “OU=AX Groups,OU=AX Roles,OU=Security Groups,OU=Users,OU=Groups,OU=Connect House,DC=ad,DC=connect-distribution,DC=co,DC=uk” -Description "AX PROD Super User - All roles apart from System Administrators" -GroupCategory Security -GroupScope Global -Server AX-DC-01
    New-AXUser -AccountType WindowsGroup -AXUserId PROSU -UserName "AX PROD - SuperUsers" -UserDomain CONNECT -Company CDS
    
    $groups = Import-Csv "C:\Users\gwoolley\Desktop\NewAX_Sec_Roles_Export2.csv"
    $newgroups = @()
    foreach ($group in $groups) {
        if($group.AOTName -contains "-SYSADMIN-" -eq $false)
        {
            $newgroups += $group 
        }
    }

    foreach ($group in $newgroups) {
      Add-AXSecurityRoleMember -AOTName $group.AOTName -AxUserID PROSU
        }







# Add UAT SysAdmin and PowerUser - Run manually per environment - Check your AOS Server with GET-AXAOS Cmd
    
    #SysAdmin

    New-ADGroup -Name "AX UAT - SysAdmins" -Path “OU=AX Groups,OU=AX Roles,OU=Security Groups,OU=Users,OU=Groups,OU=Connect House,DC=ad,DC=connect-distribution,DC=co,DC=uk” -Description "AX UAT System Administrators" -GroupCategory Security -GroupScope Global -Server AX-DC-01
    New-AXUser -AccountType WindowsGroup -AXUserId UATADM -UserName "AX UAT - SysAdmins" -UserDomain CONNECT -Company CDS
    Add-AXSecurityRoleMember -AOTName "-SYSADMIN-" -AxUserID UATADM
   
    #Super User

    New-ADGroup -Name "AX UAT - SuperUsers" -Path “OU=AX Groups,OU=AX Roles,OU=Security Groups,OU=Users,OU=Groups,OU=Connect House,DC=ad,DC=connect-distribution,DC=co,DC=uk” -Description "AX UAT Super User - All roles apart from System Administrators" -GroupCategory Security -GroupScope Global -Server AX-DC-01
    New-AXUser -AccountType WindowsGroup -AXUserId UATSU -UserName "AX UAT - SuperUsers" -UserDomain CONNECT -Company CDS
    
    $groups = Import-Csv "C:\Users\gwoolley\Desktop\NewAX_Sec_Roles_Export2.csv"
    $newgroups = @()
    foreach ($group in $groups) {
        if($group.AOTName -contains "-SYSADMIN-" -eq $false)
        {
            $newgroups += $group 
        }
    }

    foreach ($group in $newgroups) {
      Add-AXSecurityRoleMember -AOTName $group.AOTName -AxUserID UATSU
        }





# Add DEV SysAdmin and PowerUser - Run manually per environment - Check your AOS Server with GET-AXAOS Cmd
    
    
    #SysAdmin

    New-ADGroup -Name "AX DEV - SysAdmins" -Path “OU=AX Groups,OU=AX Roles,OU=Security Groups,OU=Users,OU=Groups,OU=Connect House,DC=ad,DC=connect-distribution,DC=co,DC=uk” -Description "AX DEV System Administrators" -GroupCategory Security -GroupScope Global -Server AX-DC-01
    New-AXUser -AccountType WindowsGroup -AXUserId DEVADM -UserName "AX DEV - SysAdmins" -UserDomain CONNECT -Company CDS
    Add-AXSecurityRoleMember -AOTName "-SYSADMIN-" -AxUserID DEVADM
   
    #Super User

    New-ADGroup -Name "AX DEV - SuperUsers" -Path “OU=AX Groups,OU=AX Roles,OU=Security Groups,OU=Users,OU=Groups,OU=Connect House,DC=ad,DC=connect-distribution,DC=co,DC=uk” -Description "AX DEV Super User - All roles apart from System Administrators" -GroupCategory Security -GroupScope Global -Server AX-DC-01
    New-AXUser -AccountType WindowsGroup -AXUserId DEVSU -UserName "AX DEV - SuperUsers" -UserDomain CONNECT -Company CDS
    
    $groups = Import-Csv "C:\Users\gwoolley\Desktop\NewAX_Sec_Roles_Export2.csv"
    $newgroups = @()
    foreach ($group in $groups) {
        if($group.AOTName -contains "-SYSADMIN-" -eq $false)
        {
            $newgroups += $group 
        }
    }

    foreach ($group in $newgroups) {
      Add-AXSecurityRoleMember -AOTName $group.AOTName -AxUserID DEVSU
        }




        

# Edit Role Desciptions 

    Import-Module ActiveDirectory
$groups = Import-Csv "C:\Users\gwoolley\Desktop\NewAX_Sec_Roles_Export2.csv"
foreach ($group in $groups) {
    Set-ADGroup -Identity "AX Role - $($group.name)" -Description ($group.description)

    }

    write-host ($group.description)






# New Parent AX Groups 

$groups = Import-Csv "C:\Users\gwoolley\Desktop\NewAX_Sec_Roles_Export2.csv"
foreach ($group in $groups) {
    New-ADGroup -Name "AX Dept SU - $($group.SuperGroup)" -Path “OU=AX Groups,OU=AX Roles,OU=Security Groups,OU=Users,OU=Groups,OU=Connect House,DC=ad,DC=connect-distribution,DC=co,DC=uk” -Description "AX $($group.SuperGroup) Department Managers" -GroupCategory Security -GroupScope Global -Server AX-DC-01
  }

