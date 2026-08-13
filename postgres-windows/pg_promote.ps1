function Promote-Replica
{
    #. .\check_split_brain.ps1

    param([string[]]$Server_rep,
    [string[]]$Primary)

    $Server_rep=@($Server_rep)

    $DataDir = "S:\Postgres\18.3\data"
    $DB_PORT = "5432"
    $DB_NAME = "postgres"
    $DB_USER = "postgres"
    $env:Path += ";C:\Program Files\PostgreSQL\18\bin\"
    $psqlPath = "C:\Program Files\PostgreSQL\18\bin"
  
    Write-Host "Inside the pg_promote.ps1 and printing list of replicas available"
    Start-sleep 1
    $Server=$Server_rep
    foreach($item in $Server){
	Write-Host "$item"
    }
    $new_primary=$Primary
    Write-host "new primary $($new_primary)"
    Invoke-Command `
      -ComputerName $new_primary `
      -ScriptBlock {

        & "C:\Program Files\PostgreSQL\18\bin\pg_ctl.exe" `
          promote `
          -D "S:\Postgres\18.3\data" 

    Start-Sleep 3
    }
    Invoke-Command `
      -ComputerName $new_primary `
      -ScriptBlock {

        & Get-Service -Name "postgresql-x64-18" | Set-Service -StartupType Manual -PassThru

    Start-Sleep 2
    }
  
    # update the postgres.auto.conf
    $ipRegex  = '\b(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\b'
    
    foreach($item in $Server)
    {
        if($item -ne $new_primary)
        {
            Invoke-Command `
              -ComputerName $item `
              -ScriptBlock {
           # & (Get-Content -Path "$DataDir\postgresql.auto.conf") -notmatch "primary_conninfo" | Set-Content "$DataDir\postgresql.auto.conf"
           # Add-Content -Path "$DataDir\postgresql.auto.conf" -Value "primary_conninfo = 'user=replicator passfile=''C:\\\\Users\\\\ADM90995\\\\AppData\\\\Roaming/postgresql/pgpass.conf'' channel_binding=prefer host=$($new_primary) port=5432 sslmode=prefer sslnegotiation=postgres sslcompression=0 sslcertmode=allow sslsni=1 ssl_min_protocol_version=TLSv1.2 gssencmode=disable krbsrvname=postgres gssdelegation=0 target_session_attrs=any load_balance_hosts=disable'"
           
           & (Get-Content -Path "S:\Postgres\18.3\data\postgresql.auto.conf") -replace $ipRegex, $new_primary | Set-Content -Path "S:\Postgres\18.3\data\postgresql.auto.conf"

           Restart-Service postgresql-x64-18

   
           & Get-Service -Name "postgresql-x64-18" | Set-Service -StartupType Automatic -PassThru

                Start-Sleep 2
                }
        }
        
    }
    Write-Host "$($new_primary) promoted successfully"
    
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
    Write-Output "clearing List before exiting"
    $Server = @()
    Write-Output "printing Server list"
    
}