#Rebuild Replica from Primary full Load and SYNC unlike REWIND

<#param(
        [string]$current_node
    )
#>
# PostgreSQL Replica Rebuild Script
$PSDefaultParameterValues.Clear()
$servers = @("10.0.126.118", "10.0.126.119", "10.0.126.92")
. .\check_split_brain.ps1

$Primary,$Replicas = Get-PgPrimaryReplicas -Nodes $servers

# Configuration
$PrimaryHost = "$Primary"
$PrimaryPort = "5432"
$DB_USER = "postgres"
$DB_NAME = "postgres"
$ReplicationUser = "replicator"
$PgData = "S:\Postgres\18.3\data"
$env:Path += ";C:\Program Files\PostgreSQL\18\bin\"
$PgBin = "C:\Program Files\PostgreSQL\18\bin"
$PgService = "postgresql-x64-18"
$slotResult = 0

$slotResult = (psql.exe -h $Primary -U $DB_USER -d $DB_NAME -t -c "SELECT bool_or(active)::int AS result FROM pg_replication_slots").trim()
if($slotResult -eq ""){
    $slotResult = 0
}
Write-Host "result of Slot_check : $($slotResult)"
$slotResult = Read-Host -Prompt "please enter if you want to have Replicatoin Slot 1 for Yes , 0 for No"
if($slotResult -eq 1){
$myIP = (Get-NetIPAddress -AddressFamily IPv4 -InterfaceIndex (Get-NetConnectionProfile).InterfaceIndex).IPAddress
Write-Host "Building Replica WITH Replication Slots"
Write-Host "IP for Slot naming: $($myIP)"
} else {
Write-Host "Building Replica without Replication Slots"
}

Write-Host "Stopping PostgreSQL service..."
Stop-Service -Name $PgService -Force

# Wait for service to stop
Start-Sleep -Seconds 10

Write-Host "Removing old data directory..."
if (Test-Path $PgData) {
    Remove-Item "$PgData\*" -Recurse -Force
}


$slot_name_ip=$myIP.Split('.')[3]
$slot= "standby_slot_$slot_name_ip"
# Set password for pg_basebackup
#$env:PGPASSWORD = "14hjPH@1jzs)5JXe"

Write-Host "Taking base backup (FULL LOAD) from primaryHost...$($PrimaryHost)"

& "C:\Program Files\PostgreSQL\18\bin\pg_basebackup.exe" `
    -h $PrimaryHost `
    -p $PrimaryPort `
    -U $ReplicationUser `
    -D $PgData `
    -R `
    -X stream `
    -v
#    -S $slot `
    

if ($LASTEXITCODE -ne 0) {
    Write-Error "pg_basebackup failed."
    exit 1
}

########################################################
# STEP 5 - Create replication slots
########################################################
if($slotResult -eq 1){
#create Replication Slot if not exists

    $Slot_create_119    = "SELECT pg_create_physical_replication_slot('standby_slot_119');"
    $Slot_create_92    = "SELECT pg_create_physical_replication_slot('standby_slot_92');"
    $Slot_create_118    = "SELECT pg_create_physical_replication_slot('standby_slot_118');"

    if($NewPrimary -eq "10.0.126.118")
    {
        psql.exe `
          -h $NewPrimary `
          -U postgres `
          -t `
          -c "$Slot_create_119;$Slot_create_92;"
          #-c "call slot_creation_118();"
    }elseif ($NewPrimary -eq "10.0.126.119"){
         psql.exe `
          -h $NewPrimary `
          -U postgres `
          -t `
          -c "$Slot_create_118;$Slot_create_92;"
          #-c "call slot_creation_119();"
    }else{
        psql.exe `
          -h $NewPrimary `
          -U postgres `
          -t `
          -c "$Slot_create_119;$Slot_create_118;"
#          -c "call slot_creation_92();"        
    }

Write-Host "Slot creation done"
}

$AutoConf = "S:\Postgres\18.3\data\postgresql.auto.conf"
$postgresConf = "S:\Postgres\18.3\data\postgresql.conf"

if($slotResult -eq 1){
    $Content =
    Get-Content $AutoConf |
    Where-Object {
        $_ -notmatch "^primary_conninfo" -and
        $_ -notmatch "^primary_slot_name"
        }
    $Content | Set-Content $AutoConf

    Add-Content "S:\Postgres\18.3\data\postgresql.auto.conf" `
    "primary_conninfo = 'user=replicator passfile=''C:\\\\Users\\\\ADM90995\\\\AppData\\\\Roaming/postgresql/pgpass.conf'' channel_binding=prefer host=$($PrimaryHost) port=5432 sslmode=prefer sslnegotiation=postgres sslcompression=0 sslcertmode=allow sslsni=1 ssl_min_protocol_version=TLSv1.2 gssencmode=disable krbsrvname=postgres gssdelegation=0 target_session_attrs=any load_balance_hosts=disable'"
    Add-Content "S:\Postgres\18.3\data\postgresql.auto.conf" `
    "primary_slot_name = '$Slot'"

} else {
    $Content =
    Get-Content $AutoConf |
    Where-Object {
        $_ -notmatch "^primary_conninfo" -and
        $_ -notmatch "^primary_slot_name"
        }
    $Content | Set-Content $AutoConf

    Add-Content $AutoConf `
    "primary_conninfo = 'user=replicator passfile=''C:\\\\Users\\\\ADM90995\\\\AppData\\\\Roaming/postgresql/pgpass.conf'' channel_binding=prefer host=$($PrimaryHost) port=5432 sslmode=prefer sslnegotiation=postgres sslcompression=0 sslcertmode=allow sslsni=1 ssl_min_protocol_version=TLSv1.2 gssencmode=disable krbsrvname=postgres gssdelegation=0 target_session_attrs=any load_balance_hosts=disable'"

    }

    $Content =
    Get-Content $postgresConf |
    Where-Object {
        $_ -notmatch "^primary_slot_name"
        }

    if($slotResult -eq 1){
        Add-Content $postgresConf `
        "primary_slot_name= '$Slot'"

    }else {
        Add-Content $postgresConf `
        "#primary_slot_name= '$Slot'"
    }
Write-Host "Starting PostgreSQL service..."
Start-Service -Name $PgService

Write-Host "Waiting for startup..."
Start-Sleep -Seconds 5

Write-Host "Checking replica status..."

& "$PgBin\psql.exe" `
    -U postgres `
    -d postgres `
    -c "SELECT pg_is_in_recovery();"

Write-Host "Replica rebuild completed successfully."