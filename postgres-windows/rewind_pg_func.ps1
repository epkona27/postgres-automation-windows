# PostgreSQL failback with pg_rewind
function pg_Rewind_switchOver
{

param([string[]]$Primary,[string[]]$Old_Primary)

$Server   = "localhost"
$Port     = "5432"
$User     = "postgres"
$Database = "postgres"
$DataDir = "S:\Postgres\18.3\data"

$env:Path += ";C:\Program Files\PostgreSQL\18\bin\"



Write-Host "New Primary: $Primary"
$SourceConn = "host=$($Primary) port=5432 user=postgres dbname=postgres"

Write-Host "$SourceConn"
write-Host "$DataDir"

Write-Host "Stopping PostgreSQL..."
#net stop postgresql-x64-18

Write-Host "Running pg_rewind..."

Invoke-Command `
    -ComputerName $Old_Primary `
    -ScriptBlock {
                    & net stop postgresql-x64-18

                    & "C:\Program Files\PostgreSQL\18\bin\pg_rewind.exe" `
                      --target-pgdata="$DataDir" `
                      --source-server="$SourceConn" `
                      --progress
                  }

if ($LASTEXITCODE -ne 0)
{
    Write-Error "pg_rewind failed"
    exit 1
}


Write-Host "Configuring standby..."



Invoke-Command `
    -ComputerName $Old_Primary `
    -ScriptBlock {
            New-Item `
                -Path "$DataDir\standby.signal" `
                -ItemType File `
                -Force
                #& (Get-Content -Path "$DataDir\postgresql.auto.conf") -notmatch "primary_conninfo" | Set-Content "$DataDir\postgresql.auto.conf"
                       #Add-Content -Path "$DataDir\postgresql.auto.conf" -Value "primary_conninfo = 'user=replicator passfile=''C:\\\\Users\\\\ADM90995\\\\AppData\\\\Roaming/postgresql/pgpass.conf'' channel_binding=prefer host=$($using:Primary) port=5432 sslmode=prefer sslnegotiation=postgres sslcompression=0 sslcertmode=allow sslsni=1 ssl_min_protocol_version=TLSv1.2 gssencmode=disable krbsrvname=postgres gssdelegation=0 target_session_attrs=any load_balance_hosts=disable'"
                $ipRegex  = '\b(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\b'
                & (Get-Content -Path "S:\Postgres\18.3\data\postgresql.auto.conf") -replace $ipRegex, $Primary | Set-Content -Path "S:\Postgres\18.3\data\postgresql.auto.conf"
                }

                Write-Host "Starting PostgreSQL..."
Invoke-Command -ScriptBlock {
                net start postgresql-x64-18
                Get-Service -Name "postgresql-x64-18" | Set-Service -StartupType Automatic -PassThru
                }




#psql -h $Server -p $Port -U $User -d $Database -c $Slot_create_119
#psql -h $Server -p $Port -U $User -d $Database -c $Slot_create_92

Write-Host "Secondary/Old primary/New Replica is READY FOR FAILBACK NOW"

}