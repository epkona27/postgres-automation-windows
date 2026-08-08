# PostgreSQL failback with pg_rewind


$Server   = "localhost"
$servers = @("10.0.126.118", "10.0.126.119", "10.0.126.92")
$Port     = "5432"
$User     = "postgres"
$Database = "postgres"
$DataDir = "S:\Postgres\18.3\data"
$Slot_create_119    = "SELECT pg_create_physical_replication_slot('standby_slot_119');"
$Slot_create_92    = "SELECT pg_create_physical_replication_slot('standby_slot_92');"
$Slot_create_118    = "SELECT pg_create_physical_replication_slot('standby_slot_118');"

$env:Path += ";C:\Program Files\PostgreSQL\18\bin\"

. ./check_split_brain.ps1

$Primary,$Replicas = Get-PgPrimaryReplicas -Nodes $servers
Write-Host "Current Primary: $Primary"
$SourceConn = "host=$($Primary) port=5432 user=postgres dbname=postgres"

Write-Host "$SourceConn"
write-Host "$new_conn_profile"
$myIP = (Get-NetIPAddress -AddressFamily IPv4 -InterfaceIndex (Get-NetConnectionProfile).InterfaceIndex).IPAddress
Write-Host "$myIP"

Write-Host "Current Replicas:"
foreach($item in $Replicas){
	Write-Host "$item"
}

Write-Host "Stopping PostgreSQL..."
net stop postgresql-x64-18

Write-Host "Running pg_rewind..."

pg_rewind `
  --target-pgdata=$DataDir `
  --source-server="$SourceConn" `
  --progress

if ($LASTEXITCODE -ne 0)
{
    Write-Error "pg_rewind failed"
    exit 1
}

$slot_name_ip=$myIP.Split('.')[3]
$Slot = "standby_slot_$slot_name_ip"

Write-Host "Configuring standby..."

New-Item `
   -Path "$DataDir\standby.signal" `
   -ItemType File `
   -Force

(Get-Content -Path "$DataDir\postgresql.auto.conf") -notmatch "primary_conninfo" | Set-Content "$DataDir\postgresql.auto.conf"
            Add-Content -Path "$DataDir\postgresql.auto.conf" -Value "primary_conninfo = 'user=replicator passfile=''C:\\\\Users\\\\ADM90995\\\\AppData\\\\Roaming/postgresql/pgpass.conf'' channel_binding=prefer host=$($Primary) port=5432 sslmode=prefer sslnegotiation=postgres sslcompression=0 sslcertmode=allow sslsni=1 ssl_min_protocol_version=TLSv1.2 gssencmode=disable krbsrvname=postgres gssdelegation=0 target_session_attrs=any load_balance_hosts=disable'"
$AutoConf =
        "S:\Postgres\18.3\data\postgresql.auto.conf"
$Content =
    Get-Content $AutoConf |
    Where-Object {
        $_ -notmatch "^primary_slot_name"
    }

$Content | Set-Content $AutoConf
Add-Content `
      "S:\Postgres\18.3\data\postgresql.auto.conf" `
      "primary_slot_name='$Slot'"

Write-Host "Starting PostgreSQL..."
net start postgresql-x64-18
Get-Service -Name "postgresql-x64-18" | Set-Service -StartupType Automatic -PassThru

#psql -h $Server -p $Port -U $User -d $Database -c $Slot_create_119
#psql -h $Server -p $Port -U $User -d $Database -c $Slot_create_92

Write-Host "Secondary/Old primary/New Replica is READY FOR FAILBACK NOW"