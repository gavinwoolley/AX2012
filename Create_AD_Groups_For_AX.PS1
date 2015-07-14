$groups = Import-Csv "C:\Users\gwoolley\Desktop\AX_Roles_I_Want_To_Create.csv"
foreach ($group in $groups) {
New-ADGroup -Name $group.name -Path “OU=AX Roles,OU=Security Groups,OU=Users,OU=Groups,OU=Connect House,DC=ad,DC=connect-distribution,DC=co,DC=uk” -Description $group.name -GroupCategory Security -GroupScope Global
}