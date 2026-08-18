# PostgreSQL failback with pg_rewind


$Server   = "localhost"
$servers = @("10.0.126.118", "10.0.126.119", "10.0.126.92")
$Port     = "5432"
$DB_USER     = "postgres"
$DB_NAME = "postgres"
$DataDir = "S:\Postgres\18.3\data"
$slotResult = 0
$Slot_create_119    = "SELECT pg_create_physical_replication_slot('standby_slot_119');"
$Slot_create_92    = "SELECT pg_create_physical_replication_slot('standby_slot_92');"
$Slot_create_118    = "SELECT pg_create_physical_replication_slot('standby_slot_118');"
$env:Path += ";C:\Program Files\PostgreSQL\18\bin\"
. ./check_split_brain.ps1

$Primary,$Replicas = Get-PgPrimaryReplicas -Nodes $servers
Write-Host "Current Primary: $Primary"
$SourceConn = "host=$($Primary) port=5432 user=postgres dbname=postgres"


$slotResult = (psql.exe -h $Primary -U $DB_USER -d $DB_NAME -t -c "SELECT bool_or(active)::int AS result FROM pg_replication_slots").trim()
Write-Host "result of Slot_check : $($slotResult)"
$slotResult = Read-Host -Prompt "please enter if you want to have Replicatoin Slot 1 for Yes , 0 for No"


Write-Host "$SourceConn"
write-Host "$new_conn_profile"
$myIP = (Get-NetIPAddress -AddressFamily IPv4 -InterfaceIndex (Get-NetConnectionProfile).InterfaceIndex).IPAddress
Write-Host "my IP for SLOT naming $($myIP)"

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

Write-Host "Configuring standby..."
New-Item `
   -Path "$DataDir\standby.signal" `
   -ItemType File `
   -Force

########################################################
# Create replication slots
########################################################
if($slotResult -eq 1){
#create Replication Slot if not exists

    $Slot_create_119    = "SELECT pg_create_physical_replication_slot('standby_slot_119');"
    $Slot_create_92    = "SELECT pg_create_physical_replication_slot('standby_slot_92');"
    $Slot_create_118    = "SELECT pg_create_physical_replication_slot('standby_slot_118');"

    if($Primary -eq "10.0.126.118")
    {
        psql.exe `
          -h $Primary `
          -U postgres `
          -t `
          -c "call slot_creation_118();"
    }elseif ($Primary -eq "10.0.126.119"){
         psql.exe `
          -h $Primary `
          -U postgres `
          -t `
          -c "call slot_creation_119();"
    }else{
        psql.exe `
          -h $Primary `
          -U postgres `
          -t `
          -c "call slot_creation_92();"        
    }

Write-Host "Slot creation done with stored procedure"
}

$AutoConf =
        "S:\Postgres\18.3\data\postgresql.auto.conf"

if($slotResult -eq 1){
    $slot_name_ip=$myIP.Split('.')[3]
    $Slot = "standby_slot_$slot_name_ip"
    Write-Host "Slot Name : $($Slot)"
    $Content =
        Get-Content $AutoConf |
        Where-Object {
                $_ -notmatch "^primary_conninfo" -and
                $_ -notmatch "^primary_slot_name"
        }

    $Content | Set-Content $AutoConf
    Add-Content `
          $AutoConf `
          "primary_slot_name='$Slot'"

    Add-Content `
        $AutoConf `
        "primary_conninfo = 'user=replicator passfile=''C:\\\\Users\\\\ADM90995\\\\AppData\\\\Roaming/postgresql/pgpass.conf'' channel_binding=prefer host=$($Primary) port=5432 sslmode=prefer sslnegotiation=postgres sslcompression=0 sslcertmode=allow sslsni=1 ssl_min_protocol_version=TLSv1.2 gssencmode=disable krbsrvname=postgres gssdelegation=0 target_session_attrs=any load_balance_hosts=disable'"

    
        $postgresConf = "S:\Postgres\18.3\data\postgresql.conf"
        (Get-Content $postgresConf) -replace '^\s*.*primary_slot_name\s*=\s*.*$', "primary_slot_name = '$Slot'" | Set-Content $postgresConf

} else {
    $Content =
        Get-Content $AutoConf |
        Where-Object {
            $_ -notmatch "^primary_conninfo" -and
            $_ -notmatch "^primary_slot_name"
        }

    $Content | Set-Content $AutoConf
    Add-Content $AutoConf `
    "primary_conninfo = 'user=replicator passfile=''C:\\\\Users\\\\ADM90995\\\\AppData\\\\Roaming/postgresql/pgpass.conf'' channel_binding=prefer host=$($Primary) port=5432 sslmode=prefer sslnegotiation=postgres sslcompression=0 sslcertmode=allow sslsni=1 ssl_min_protocol_version=TLSv1.2 gssencmode=disable krbsrvname=postgres gssdelegation=0 target_session_attrs=any load_balance_hosts=disable'"
 `
    $postgresConf = "S:\Postgres\18.3\data\postgresql.conf"
    #(Get-Content $postgresConf) | ForEach-Object { $_ -replace '^(#)primary_slot_name.*$', "#primary_slot_name =''" } | Set-Content $postgresConf
    (Get-Content $postgresConf) -replace '^(\s*)(primary_slot_name\s*=\s*.*)$', '#$2' | Set-Content $postgresConf
    Write-Host "removing primary slot entry from postgres.conf"
                  
}


Write-Host "Starting PostgreSQL..."
net start postgresql-x64-18
Get-Service -Name "postgresql-x64-18" | Set-Service -StartupType Automatic -PassThru

#psql -h $Server -p $Port -U $User -d $Database -c $Slot_create_119
#psql -h $Server -p $Port -U $User -d $Database -c $Slot_create_92

Write-Host "Secondary/Old primary/New Replica is READY FOR FAILBACK NOW"