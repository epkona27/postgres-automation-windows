########################################################
# PostgreSQL Planned Switchover
########################################################

param(
        [string]$new_primary
    )

$PSDefaultParameterValues.Clear()
 $servers = @("10.0.126.118", "10.0.126.119", "10.0.126.92")
. .\check_split_brain.ps1

$Primary,$Replicas = Get-PgPrimaryReplicas -Nodes $servers
$NewPrimary = $new_primary
$OldPrimary = $Primary

$PGService = "postgresql-x64-18"
$DataDir = "S:\Postgres\18.3\data"
$DB_PORT = "5432"
$DB_NAME = "postgres"
$DB_USER = "postgres"
$env:Path += ";C:\Program Files\PostgreSQL\18\bin\"
$psqlPath = "C:\Program Files\PostgreSQL\18\bin"
$slotResult = 0

Write-Host "Existing Primary is $Primary"
if($OldPrimary -eq $new_primary){
    Write-Host "$($NewPrimary) is already the current primary, Please pick another node, nothing can be done here"
    Break
}
if($new_primary -notin $Replicas){
    Write-host "Variable #new_primary Input needs to be part of replica list: $($Replicas -join ', ')"
    break
}

$slotResult = (psql.exe -h $Primary -U $DB_USER -d $DB_NAME -t -c "SELECT bool_or(active)::int AS result FROM pg_replication_slots").trim()
if($slotResult -eq ""){
    $slotResult = 0
}
Write-Host "result of Slot_check : $($slotResult)"
#$userInput4Slots = Read-Host -Prompt "please enter if you want to have Replicatoin Slot 1 for Yes , 0 for No"
if (($userInput4Slots = Read-Host -Prompt "please enter if you want to have Replicatoin Slot 1 for Yes , 0 for No") -ne "") { $slotResult = $userInput4Slots }
if ($userInput4Slots -notIn @('0', '1')) {
    Throw "Error: You must enter '0' or '1'."
}
Write-Host "Replication-Slot final call is $($slotResult)"

if($slotResult -eq 1)
{
    $slot_flag="WITH REPLICATION SLOTS"
} else {
    $slot_flag="NO REPL SLOTS"
}

########################################################
# STEP 1 - Verify standby is caught up
########################################################

Write-Host "Checking replication lag on all Replicas..."

foreach($item in $Replicas)
    {
    $Lag = psql.exe `
        -h $item `
        -U postgres `
        -t -A `
        -c "SELECT COALESCE(EXTRACT(EPOCH FROM now()-pg_last_xact_replay_timestamp()),0);"
    $Lag = [double]$Lag

    if($Lag -gt 1)
    {
        throw "Replication lag on $item is $Lag seconds."
    }
    else{
        Write-Host "Replica $($item) is synchronized."
    }
    }
#Break
########################################################
# STEP 2 - Create restore point
########################################################

$restore_point = (psql `
   -h $OldPrimary `
   -U postgres `
   -t -A `
   -c "SELECT pg_create_restore_point('SWITCHOVER')") -split "`r?`n" | Where-Object { $_ -ne "" }

Write-Host "Restore POINT on Primary : $($restore_point)"

########################################################
# STEP 3 - Promote standby
########################################################

#modifying Replica list as one of them is becoming primary
#$Replicas_bkp=$Replicas
#$Replicas | Where-Object { $_ -ne $new_primary }
foreach($item in $Replicas){
do {
    write-Host "waiting for Restore point to be ready on $($item)"
    $lsn_newPrim = Invoke-Command `
                  -ComputerName $item `
                  -ScriptBlock {
                     $catchup_point = & "C:\Program Files\PostgreSQL\18\bin\psql.exe" `
                     -U postgres `
                     -d postgres `
                   -t -A `
                   -c "SELECT pg_last_wal_replay_lsn()>= '$using:restore_point'::pg_lsn;"
                   $catchup_point.Trim()                
                    }
                    $i++ 
} until ($lsn_newPrim -eq "t")
Write-Host "Restore POINT on Replica $($item) is caught up to : $($restore_point)"
}

Write-Host "Promoting $NewPrimary"
Invoke-Command `
  -ComputerName $NewPrimary `
  -ArgumentList $NewPrimary `
  -ScriptBlock {

    param($NewPrimary)

    $slot_name_ip=$NewPrimary.Split('.')[3]
    $Slot = "standby_slot_$slot_name_ip"

    $postgresConf = "S:\Postgres\18.3\data\postgresql.conf"
    (Get-Content $postgresConf) -replace '^\s*.*primary_slot_name\s*=\s*.*$', "primary_slot_name = '$Slot'" | Set-Content $postgresConf

    & "C:\Program Files\PostgreSQL\18\bin\pg_ctl.exe" `
      promote `
      -D "S:\Postgres\18.3\data"

    & Get-Service -Name "postgresql-x64-18" | Set-Service -StartupType Manual -PassThru
}

Start-Sleep 2

########################################################
# STEP 4 - Validate promotion
########################################################

$Role = psql `
    -h $NewPrimary `
    -U postgres `
    -t -A `
    -c "SELECT pg_is_in_recovery();"

if($Role.Trim() -ne "f")
{
    throw "Promotion failed."
}

Write-Host "$NewPrimary is now The new Primary."

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

########################################################
# STEP 6 - Reconfigure replicas
########################################################
Write-Host "Reconfiguring Replicas to the New Primary"

foreach($Replica in $Replicas)
{
    if($Replica -ne $NewPrimary -and $Replica -ne $OldPrimary){
        if($slotResult -eq 1)
        {
            #$slot_name_ip=$Replica.Split('.')[3]
            #$Slot = "standby_slot_$slot_name_ip"
            Invoke-Command `
              -ComputerName $Replica `
              -ArgumentList $NewPrimary,$Replica `
              -ScriptBlock {

                param($NewPrimary,$Replica)

                $slot_name_ip=$Replica.Split('.')[3]
                $Slot = "standby_slot_$slot_name_ip"

                Write-Host "Since Slot Option is choosen we are checking for slots $($Slot)"
                $AutoConf =
                "S:\Postgres\18.3\data\postgresql.auto.conf"

                $Content =
                Get-Content $AutoConf |
                Where-Object {
                    $_ -notmatch "^primary_conninfo" -and
                    $_ -notmatch "^primary_slot_name"
                }

                $Content | Set-Content $AutoConf

                Add-Content $AutoConf `
                "primary_slot_name = '$Slot'"

                Add-Content $AutoConf `
                "primary_conninfo = 'user=replicator passfile=''C:\\\\Users\\\\ADM90995\\\\AppData\\\\Roaming/postgresql/pgpass.conf'' channel_binding=prefer host=$($using:NewPrimary) port=5432 sslmode=prefer sslnegotiation=postgres sslcompression=0 sslcertmode=allow sslsni=1 ssl_min_protocol_version=TLSv1.2 gssencmode=disable krbsrvname=postgres gssdelegation=0 target_session_attrs=any load_balance_hosts=disable'"

                $postgresConf = "S:\Postgres\18.3\data\postgresql.conf"
                #'^(\s*)(primary_slot_name\s*=)', '$1# $2'     -----   '^(\s*)#\s*(?=primary_slot_name\s*=)'
                #(Get-Content $postgresConf) |  ForEach-Object { $_ -replace "^#primary_slot_name.*$","primary_slot_name ='$Slot'" } | Set-Content $postgresConf
                #(Get-Content $postgresConf) |  ForEach-Object { $_ -replace '^(#)primary_slot_name.*$',"primary_slot_name ='$Slot'" } | Set-Content $postgresConf
                #(Get-Content $postgresConf) -replace '^(\s*)#\s*(?=primary_slot_name\s*=)', '$1' | Set-Content $postgresConf
                (Get-Content $postgresConf) -replace '^\s*.*primary_slot_name\s*=\s*.*$', "primary_slot_name = '$Slot'" | Set-Content $postgresConf
                <#(Get-Content $postgresConf) |
                    ForEach-Object {
                    if ($_ -match '^\s*#\s*primary_slot_name\s*=') {
                        $_.Replace('#','').TrimStart()
                        }
                        else {
                        $_
                        }
                    } | Set-Content $postgresConf #>

                Start-sleep 5
                Restart-Service postgresql-x64-18
                Start-sleep 1
                } 
        
            } else {

                    Write-Host "Since Slot Option is Not choosen we are remove any existing  slots"
                    Invoke-Command `
                  -ComputerName $Replica `
                  -ArgumentList $NewPrimary `
                  -ScriptBlock {

                    param($NewPrimary)

                    $AutoConf =
                    "S:\Postgres\18.3\data\postgresql.auto.conf"

                    $Content = 
                    Get-Content $AutoConf |
                    Where-Object {
                        $_ -notmatch "^primary_conninfo" -and
                        $_ -notmatch "^primary_slot_name"
                        }

                    $Content | Set-Content $AutoConf

                    Add-Content $AutoConf `
                    "primary_conninfo = 'user=replicator passfile=''C:\\\\Users\\\\ADM90995\\\\AppData\\\\Roaming/postgresql/pgpass.conf'' channel_binding=prefer host=$($using:NewPrimary) port=5432 sslmode=prefer sslnegotiation=postgres sslcompression=0 sslcertmode=allow sslsni=1 ssl_min_protocol_version=TLSv1.2 gssencmode=disable krbsrvname=postgres gssdelegation=0 target_session_attrs=any load_balance_hosts=disable'"
                
                    $postgresConf = "S:\Postgres\18.3\data\postgresql.conf"
                    #(Get-Content $postgresConf) |  ForEach-Object { $_ -replace '^primary_slot_name.*$', "#primary_slot_name" } | Set-Content $postgresConf
                    (Get-Content $postgresConf) -replace '^(\s*)(primary_slot_name\s*=\s*.*)$', '#$2' | Set-Content $postgresConf

                    Write-Host "removing entry from postgres.conf"
                    Start-sleep 5
                    Restart-Service postgresql-x64-18
                    Start-sleep 2
                }
            Write-Host "Reconfiguring the replicas is done"
          }
        }
 }


########################################################
# STEP 7 - Rewind former primary
########################################################

Invoke-Command `
 -ComputerName $OldPrimary `
 -ArgumentList $NewPrimary,$OldPrimary,$slotResult `
 -ScriptBlock {

    param($NewPrimary,$OldPrimary,$slotResult)
    
    Stop-Service postgresql-x64-18
    $env:Path += ";C:\Program Files\PostgreSQL\18\bin\"
    

    Write-Host "Rewinding Former Primary $OldPrimary and checking for slot $($Slot)"

    pg_rewind `
       --target-pgdata="S:\Postgres\18.3\data" `
       --source-server="host=$NewPrimary port=5432 user=postgres dbname=postgres" `
       --progress

    if($LASTEXITCODE -ne 0)
    {
        throw "pg_rewind failed"
    }

    New-Item `
      -Path "S:\Postgres\18.3\data\standby.signal" `
      -ItemType File `
      -Force

    $AutoConf =
        "S:\Postgres\18.3\data\postgresql.auto.conf"
    if($slotResult -eq 1)
        {
        #Clear-Variable -Name slot_name_ip,Slot
        $slot_name_ip=$OldPrimary.Split('.')[3]
        $Slot = "standby_slot_$slot_name_ip"
        Write-Host "checking for Old Primary slots $($Slot)"
            $Content =
            Get-Content $AutoConf |
            Where-Object {
                $_ -notmatch "^primary_conninfo" -and
                $_ -notmatch "^primary_slot_name"
            }
            $Content | Set-Content $AutoConf
              Add-Content `
              $AutoConf `
              "primary_conninfo = 'user=replicator passfile=''C:\\\\Users\\\\ADM90995\\\\AppData\\\\Roaming/postgresql/pgpass.conf'' channel_binding=prefer host=$($using:NewPrimary) port=5432 sslmode=prefer sslnegotiation=postgres sslcompression=0 sslcertmode=allow sslsni=1 ssl_min_protocol_version=TLSv1.2 gssencmode=disable krbsrvname=postgres gssdelegation=0 target_session_attrs=any load_balance_hosts=disable'"
          
              Add-Content `
              $AutoConf `
              "primary_slot_name='$Slot'"

            $postgresConf = "S:\Postgres\18.3\data\postgresql.conf"
            #(Get-Content $postgresConf) |  ForEach-Object { $_ -replace "^#primary_slot_name.*$","primary_slot_name ='$Slot'" } | Set-Content $postgresConf
            #(Get-Content $postgresConf) |  ForEach-Object { $_ -replace '^(#)primary_slot_name.*$',"primary_slot_name ='$Slot'" } | Set-Content $postgresConf
            # (Get-Content $postgresConf) -replace '^(\s*)#\s*(?=primary_slot_name\s*=)', '$1' | Set-Content $postgresConf
            (Get-Content $postgresConf) -replace '^\s*.*primary_slot_name\s*=\s*.*$', "primary_slot_name = '$Slot'" | Set-Content $postgresConf
        }
        else
        {
            $Content =
            Get-Content $AutoConf |
            Where-Object {
                $_ -notmatch "^primary_conninfo" -and
                $_ -notmatch "^primary_slot_name"
            }
            $Content | Set-Content $AutoConf
            Add-Content `
                $AutoConf `
                "primary_conninfo = 'user=replicator passfile=''C:\\\\Users\\\\ADM90995\\\\AppData\\\\Roaming/postgresql/pgpass.conf'' channel_binding=prefer host=$($using:NewPrimary) port=5432 sslmode=prefer sslnegotiation=postgres sslcompression=0 sslcertmode=allow sslsni=1 ssl_min_protocol_version=TLSv1.2 gssencmode=disable krbsrvname=postgres gssdelegation=0 target_session_attrs=any load_balance_hosts=disable'"
         
            $postgresConf = "S:\Postgres\18.3\data\postgresql.conf"
            #(Get-Content $postgresConf) | ForEach-Object { $_ -replace '^primary_slot_name.*$', "#primary_slot_name =''" } | Set-Content $postgresConf
            (Get-Content $postgresConf) -replace '^(\s*)(primary_slot_name\s*=\s*.*)$', '#$2' | Set-Content $postgresConf
         }
    
    Start-sleep 1
    Start-Service postgresql-x64-18
    & Get-Service -Name "postgresql-x64-18" | Set-Service -StartupType Automatic -PassThru
    Start-sleep 1
}

########################################################
# STEP 8 - Validate final cluster
########################################################

Write-Host ""
Write-Host "Double checking Replication status on all replicas including the Former Primary"
Start-sleep 2

$Replicas = @()
$Replicas = (psql.exe -h $NewPrimary -p $DB_PORT -U $DB_USER -d $DB_NAME -At -c "select client_addr from pg_stat_replication order by 1 DESC") -split "`r?`n" | Where-Object { $_ -ne "" }
foreach($item in $Replicas)
    {

    Write-host "checking replication status on replica $($item)"

   	    psql `
   -h $item `
   -U postgres `
   -c "
    SELECT COALESCE(EXTRACT(EPOCH FROM now()-pg_last_xact_replay_timestamp()),0) as LAG_in_SECS
    "

    Write-Host ""
    Write-Host "Switchover completed."

    }

     Write-host "checking replication status on Primary $($NewPrimary)"
   	    psql `
       -h $NewPrimary `
       -U postgres `
       -c "
        SELECT
        application_name,
        client_addr,
        state,
        sync_state
        FROM pg_stat_replication
        ORDER BY application_name;
        "
        Start-Sleep 1

########################################################
# STEP 8 - Fixing Startup to Streaming 
########################################################

    $replica_state=(psql `
   -h $NewPrimary `
   -U postgres `
   -t -A `
   -c "SELECT client_addr FROM pg_stat_replication where state='startup';")

    if($replica_state){
    Write-Host "Check if any server hold up in startup mode"
    Write-Host "List of servers with State in 'Startup' Mode - that needs a rewind or rebuild : $($replica_state -join ', ')"
    }
    foreach($j in $replica_state)
    {
            Write-Host "fixing the Replica's Startup State for $($j)"
            $Primary=$new_primary
            Invoke-Command `
              -ComputerName $j `
              -ArgumentList $Primary,$slotResult,$DataDir,$j `
              -ScriptBlock {

                param($Primary,$slotResult,$DataDir,$j)

                Write-Host "Current Primary: $Primary"
                $SourceConn = "host=$($Primary) port=5432 user=postgres dbname=postgres"
                Write-Host "Stopping PostgreSQL..."
                Start-Sleep -Seconds 2
                Stop-Service postgresql-x64-18
                $env:Path += ";C:\Program Files\PostgreSQL\18\bin\"

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

                $AutoConf =
                        "S:\Postgres\18.3\data\postgresql.auto.conf"

                if($slotResult -eq 1){
                    Clear-Variable -Name slot_name_ip,Slot
                    $slot_name_ip=$j.Split('.')[3]
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
                          "primary_slot_name ='$Slot'"

                    Add-Content `
                        $AutoConf `
                        "primary_conninfo = 'user=replicator passfile=''C:\\\\Users\\\\ADM90995\\\\AppData\\\\Roaming/postgresql/pgpass.conf'' channel_binding=prefer host=$($Primary) port=5432 sslmode=prefer sslnegotiation=postgres sslcompression=0 sslcertmode=allow sslsni=1 ssl_min_protocol_version=TLSv1.2 gssencmode=disable krbsrvname=postgres gssdelegation=0 target_session_attrs=any load_balance_hosts=disable'"

                    $postgresConf = "S:\Postgres\18.3\data\postgresql.conf"
                    #(Get-Content $postgresConf) |  ForEach-Object { $_ -replace "^#primary_slot_name.*$","primary_slot_name ='$Slot'" } | Set-Content $postgresConf
                    #(Get-Content $postgresConf) | ForEach-Object { $_ -replace '^(#)primary_slot_name.*$',"primary_slot_name = '$Slot'" } | Set-Content $postgresConf
                    #(Get-Content $postgresConf) -replace '^(\s*)#\s*(?=primary_slot_name\s*=)', '$1' | Set-Content $postgresConf
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
                 
                    $postgresConf = "S:\Postgres\18.3\data\postgresql.conf"
                    #(Get-Content $postgresConf) | ForEach-Object { $_ -replace '^(#)primary_slot_name.*$', "#primary_slot_name =''" } | Set-Content $postgresConf
                    (Get-Content $postgresConf) -replace '^(\s*)(primary_slot_name\s*=\s*.*)$', '#$2' | Set-Content $postgresConf
                    Write-Host "removing primary slot entry from postgres.conf"
                  
                }
                }
            Start-Sleep -Seconds 2
            Write-Host "Starting PostgreSQL..."
            Start-Service postgresql-x64-18
            Start-Sleep -Seconds 2
            Get-Service -Name "postgresql-x64-18" | Set-Service -StartupType Automatic -PassThru

            #psql -h $Server -p $Port -U $User -d $Database -c $Slot_create_119
            #psql -h $Server -p $Port -U $User -d $Database -c $Slot_create_92

             psql `
                -h $NewPrimary `
                -U postgres `
                -c "
                SELECT
                application_name,
                client_addr,
                state,
                sync_state
                FROM pg_stat_replication
                ORDER BY application_name;
                "
            }

    Start-Sleep 1

    if($slotResult)
    {
         Write-Host "Printing slots info - status"
        psql `
                -h $NewPrimary `
                -U postgres `
                -c "SELECT slot_name, plugin, slot_type, active, wal_status FROM pg_replication_slots"
    }
    Write-Host "Switchover completed. AND Slots: $($slot_flag)"
