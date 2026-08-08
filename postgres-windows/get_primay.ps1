$Nodes = @(
    "10.0.126.118",
    "10.0.126.119",
    "10.0.126.92"
)
. .\check_split_brain.ps1
#. .\iden_newPrimary.ps1
$Primary,$Replicas = Get-PgPrimaryReplicas -Nodes $Nodes


Write-Host "Current Primary: $Primary"
Write-Host "Current Replicas:"
foreach($item in $Replicas){
	Write-Host "$item"
}