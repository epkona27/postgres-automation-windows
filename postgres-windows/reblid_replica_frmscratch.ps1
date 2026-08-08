#Rebuild Replica from Primary full Load and SYNC unlike REWIND

param(
        [string]$current_node
    )

# PostgreSQL Replica Rebuild Script

 $servers = @("10.0.126.118", "10.0.126.119", "10.0.126.92")
. .\check_split_brain.ps1

$Primary,$Replicas = Get-PgPrimaryReplicas -Nodes $servers

# Configuration
$PrimaryHost = "$Primary"
$PrimaryPort = "5432"
$ReplicationUser = "replicator"
$PgData = "S:\Postgres\18.3\data"
$env:Path += ";C:\Program Files\PostgreSQL\18\bin\"
$PgBin = "C:\Program Files\PostgreSQL\18\bin"
$PgService = "postgresql-x64-18"

Write-Host "Stopping PostgreSQL service..."
Stop-Service -Name $PgService -Force

# Wait for service to stop
Start-Sleep -Seconds 10

Write-Host "Removing old data directory..."
if (Test-Path $PgData) {
    Remove-Item "$PgData\*" -Recurse -Force
}


$slot_name_ip=$current_node.Split('.')[3]
$slot= "standby_slot_$slot_name_ip"
# Set password for pg_basebackup
#$env:PGPASSWORD = "14hjPH@1jzs)5JXe"

Write-Host "Taking base backup from primary..."

& "$PgBin\pg_basebackup.exe" `
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
#reconfigure the right primary slot:
    #primary_slot_name = 'standby_slot_92'



$AutoConf = "S:\Postgres\18.3\data\postgresql.auto.conf"
$postgresConf = "S:\Postgres\18.3\data\postgresql.conf"

$Content =
Get-Content $AutoConf |
Where-Object {
    $_ -notmatch "^primary_conninfo" -and
    $_ -notmatch "^primary_slot_name"
}

$Content | Set-Content $AutoConf

Add-Content $AutoConf `
"primary_conninfo = 'user=replicator passfile=''C:\\\\Users\\\\ADM90995\\\\AppData\\\\Roaming/postgresql/pgpass.conf'' channel_binding=prefer host=$($PrimaryHost) port=5432 sslmode=prefer sslnegotiation=postgres sslcompression=0 sslcertmode=allow sslsni=1 ssl_min_protocol_version=TLSv1.2 gssencmode=disable krbsrvname=postgres gssdelegation=0 target_session_attrs=any load_balance_hosts=disable'"

Add-Content $AutoConf `
"primary_slot_name = '$Slot'"

$Content =
Get-Content $postgresConf |
Where-Object {
    $_ -notmatch "^primary_slot_name"
}

$Content | Set-Content $postgresConf

Add-Content $postgresConf `
"primary_slot_name= '$Slot'"

Write-Host "Starting PostgreSQL service..."
Start-Service -Name $PgService

Write-Host "Waiting for startup..."
Start-Sleep -Seconds 15

Write-Host "Checking replica status..."

& "$PgBin\psql.exe" `
    -U postgres `
    -d postgres `
    -c "SELECT pg_is_in_recovery();"

Write-Host "Replica rebuild completed successfully."