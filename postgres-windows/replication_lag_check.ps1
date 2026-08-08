########################################################
# PostgreSQL Replication Lag
########################################################

 $servers = @("10.0.126.118", "10.0.126.119", "10.0.126.92")
. .\check_split_brain.ps1

$Primary,$Replicas = Get-PgPrimaryReplicas -Nodes $servers

$PGService = "postgresql-x64-18"
$DataDir = "S:\Postgres\18.3\data"
$DB_PORT = "5432"
$DB_NAME = "postgres"
$DB_USER = "postgres"
$env:Path += ";C:\Program Files\PostgreSQL\18\bin\"
$psqlPath = "C:\Program Files\PostgreSQL\18\bin"

########################################################
# STEP 1 - Verify standby is caught up
########################################################

Write-Host "-------PRIMARY IS $($Primary)-------"
Write-Host "Checking replication lag on all Replicas..."

foreach($item in $Replicas)
    {
    $Lag = psql.exe `
        -h $item `
        -U postgres `
        -t -A `
        -c "SELECT COALESCE(EXTRACT(EPOCH FROM now()-pg_last_xact_replay_timestamp()),0);"
    $Lag = [double]$Lag

    Write-Host "------$($item)--------"
    Write-Host "Replication Lag is: $($Lag)"

    if($Lag -gt 1)
    {
        throw "Replication lag on $item is $Lag seconds."
    }
    else{
        Write-Host "Replica is synchronized."
    }
    Write-Host "--------------"
    }