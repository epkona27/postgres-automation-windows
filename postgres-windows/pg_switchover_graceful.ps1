$ip = "192.168.1.154"
    param(
        [string]$new_primary
    )

    $servers = @("10.0.126.118", "10.0.126.119", "10.0.126.92")

    . .\check_split_brain.ps1
    . .\rewind_pg_func.ps1

    $Primary,$Replicas = Get-PgPrimaryReplicas -Nodes $servers
    $DataDir = "S:\Postgres\18.3\data"
    $DB_PORT = "5432"
    $DB_NAME = "postgres"
    $DB_USER = "postgres"
    $env:Path += ";C:\Program Files\PostgreSQL\18\bin\"
    $psqlPath = "C:\Program Files\PostgreSQL\18\bin"
  
    Write-Host "Inside the switchover.ps1"
    Write-host "new primary $($new_primary)"
    Start-sleep 1
    $Servers=$Replicas
    foreach($item in $Replicas){
	Write-Host "$item"
    }

    Write-Host "Checking replication lag..."
    foreach($item in $Servers)
    {
    $Lag = psql.exe `
        -h $item `
        -U postgres `
        -t -A `
        -c "SELECT COALESCE(EXTRACT(EPOCH FROM now()-pg_last_xact_replay_timestamp()),0);"
    $Lag = [double]$Lag

    if($Lag -gt 3)
    {
        throw "Replication lag on $item is $Lag seconds."
    }
    else{
        Write-Host "Replica synchronized."
    }
    }

########################################################
# STEP 2 - Create restore point
########################################################

  & "C:\Program Files\PostgreSQL\18\bin\psql.exe" `
                -U $DB_USER `
                -h $Primary `
                -d $DB_NAME `
                -p 5432 `
                -c "SELECT pg_create_restore_point('SWITCHOVER');"
            
    #Wait-Debugger
    Start-Sleep 5
   $Old_primary=$Primary
    
    Invoke-Command `
      -ComputerName $new_primary `
      -ScriptBlock {

        & "C:\Program Files\PostgreSQL\18\bin\pg_ctl.exe" `
          promote `
          -D "S:\Postgres\18.3\data" 
        & Get-Service -Name "postgresql-x64-18" | Set-Service -StartupType Manual -PassThru

    Start-Sleep 3
    }
    #$Replicas +=$Old_primary

    Write-Host "$($new_primary) promoted successfully, Now repointing replicas to New Primary"
    foreach($item in $Replicas)
        {
            Write-Host " Repointing replica $($item) to the $($new_primary)"
        }


    # update the postgres.auto.conf
    #$Replicas.Remove($new_primary)
    $ipRegex  = '\b(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\b'
    
    foreach($item in $Replicas)
    {
        if([ipaddress]$item -ne [ipaddress]$new_primary)
        {
            Write-Host "Modifying Replica's $($item) Primary_Conninfo to point to new pimary"
            Invoke-Command `
              -ComputerName $item `
              -ScriptBlock {
                   #& (Get-Content -Path "$using:DataDir\postgresql.auto.conf") -notmatch "primary_conninfo" | Set-Content "$using:DataDir\postgresql.auto.conf"
                         #Add-Content -Path "$using:DataDir\postgresql.auto.conf" -Value "primary_conninfo = 'user=replicator passfile=''C:\\\\Users\\\\ADM90995\\\\AppData\\\\Roaming/postgresql/pgpass.conf'' channel_binding=prefer host=$($using:new_primary) port=5432 sslmode=prefer sslnegotiation=postgres sslcompression=0 sslcertmode=allow sslsni=1 ssl_min_protocol_version=TLSv1.2 gssencmode=disable krbsrvname=postgres gssdelegation=0 target_session_attrs=any load_balance_hosts=disable'"
                    $ipRegex  = '\b(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\b' 
                    & (Get-Content -Path "S:\Postgres\18.3\data\postgresql.auto.conf") -replace $using:ipRegex, $using:new_primary | Set-Content -Path "S:\Postgres\18.3\data\postgresql.auto.conf"
                    }
            Invoke-Command -ScriptBlock {
                    & Restart-Service postgresql-x64-18
                    & Get-Service -Name "postgresql-x64-18" | Set-Service -StartupType Automatic -PassThru
                    }
            Start-Sleep 2
              
        }
        
    }
    
    #calling rewind function on old primary

    #rewind_pg_func.ps1 -Primary $new_primary -Old_Primary $Old_primary 

    ##rewind the old Primary
    #Invoke-Command -ComputerName "$($Old_primary)" -ScriptBlock { & "C:\DBA\Postgre_PS_scripts_FailOver\pg_rewind_script.ps1" }
    pg_Rewind_switchOver -Old_Primary $Old_primary -Primary $new_primary

    $Replicas +=$Old_primary
    $Replicas = $Replicas | Where-Object { $_ -ne $new_primary }
    foreach($item in $Replicas)
    {
        Write-Host "Replica : $($item)"
    }

    
    #create Replication Slot if not exists

    $Slot_create_119    = "SELECT pg_create_physical_replication_slot('standby_slot_119');"
    $Slot_create_92    = "SELECT pg_create_physical_replication_slot('standby_slot_92');"
    $Slot_create_118    = "SELECT pg_create_physical_replication_slot('standby_slot_118');"

    if($new_primary -eq "10.0.126.118")
    {
        psql.exe `
          -h $new_primary `
          -U postgres `
          -t `
          -c "call slot_creation_118();"
    }elseif ($new_primary -eq "10.0.126.119"){
         psql.exe `
          -h $new_primary `
          -U postgres `
          -t `
          -c "call slot_creation_119();"
    }else{
        psql.exe `
          -h $new_primary `
          -U postgres `
          -t `
          -c "call slot_creation_92();"        
    }

    $Role = psql.exe `
      -h $new_primary `
      -U postgres `
      -t `
      -c "SELECT pg_is_in_recovery();"

    if($Role.Trim() -eq "f")
    {
        Write-Host "Promotion done succesfully"
    }
    else{
        throw "Promotion failed"
    }
