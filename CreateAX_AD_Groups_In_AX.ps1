. "C:\Program Files\Microsoft Dynamics AX\60\ManagementUtilities\Microsoft.Dynamics.ManagementUtilities.ps1"
$groups = Import-Csv "C:\Users\gwoolley\Desktop\AX_Roles_I_Want_To_Create.csv"
foreach ($group in $groups) 
{
New-AXUser -AccountType WindowsGroup -AXUserId $group.ID -UserName $group.Name -UserDomain CONNECT -Company CDS
}

