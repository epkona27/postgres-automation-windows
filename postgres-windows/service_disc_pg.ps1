# 1. Define the service to discover and the target script path
#$ServiceName = "postgresql-x64-18" # Example: Print POSTGRES service

# 1. List all your PostgreSQL servers
$servers = @("10.0.126.118", "10.0.126.119", "10.0.126.92")
$env:Path += ";C:\Program Files\PostgreSQL\18\bin\"

# --- CONFIGURATION ---
$DB_SERVER ="10.0.126.118"
$DataDir = "S:\Postgres\18.3\data"
$DB_PORT = "5432"
$DB_NAME = "postgres"
$DB_USER = "postgres"
$DB_PASSWORD = "Z2`rZv*K5kF$KOnb;?g:"

. .\check_split_brain.ps1
. .\pg_promote.ps1

# Set path to psql.exe
$psqlPath = "C:\Program Files\PostgreSQL\18\bin"

# Connection arguments
$connArgs = "-h $DB_SERVER -p $DB_PORT -U $DB_USER -d $DB_NAME -c 'SELECT 1;'".Trim()

$old_primary=0
$Replicas=[System.Collections.Generic.List[string]]::new()
$Primary,$Replicas = Get-PgPrimaryReplicas -Nodes $servers
Write-Host "Current Primary: $Primary"
$bkp_replicas=$Replicas

Write-Host "Pick this Replicas if decide to failover:"
Write-Host $Replicas[0]
$new_primary=$Replicas[0]

# Keep running forever
while ($true) {
    # 1. Test the TCP port
    $isPortOpen = (Test-NetConnection -ComputerName $Primary -Port $DB_PORT -ErrorAction SilentlyContinue).TcpTestSucceeded
    
    if ($isPortOpen) {
        # 2. Port is open, test actual database connection using psql
        $output = & $psqlPath\psql.exe -h $Primary -p $DB_PORT -U $DB_USER -d $DB_NAME -c 'SELECT 1;' 2>&1 | Out-String

                
        if ($LASTEXITCODE -eq 0) {
            Write-Host "$(Get-Date) - SUCCESS: Connected and queried PostgreSQL - Current PRIMARY server: $($Primary)" -ForegroundColor Green
            $Replicas = @() 
            $Replicas = (psql.exe -h $Primary -p $DB_PORT -U $DB_USER -d $DB_NAME -At -c "select client_addr from pg_stat_replication order by 1 DESC") -split "`r?`n" | Where-Object { $_ -ne "" }
            if($($Replicas.count) -gt 1){
                $new_primary=$Replicas[0]
            }
            else{
                $new_primary=$Replicas
            }
            Write-Host "count of Replica list: $($Replicas.count)"
            Write-Host "Potential New Primary $($new_primary)"
            $i=1
            foreach($item in $Replicas){
                Write-Host "Replica $($i): $($item)"
                $i+=1
            }
                       
        } else {
            Write-Host "$(Get-Date) - ERROR: Port is open, but PostgreSQL rejected the query." -ForegroundColor Yellow
            Write-Host $output -ForegroundColor DarkYellow
        }
    } else {
        Write-Host "$(Get-Date) - CRITICAL: Cannot connect to server $($Primary) on port $DB_PORT. Will trigger Failover" -ForegroundColor Red
        Write-Host "Waiting 10 secs to rule out Network Glitch before trigger Failover"
        Start-Sleep 5
        $double_check=(Test-NetConnection -ComputerName $Primary -Port $DB_PORT -ErrorAction SilentlyContinue).TcpTestSucceeded
        if(!$double_check)
            {
                Write-Host "Triggering FailOver to $($new_primary)"
                Start-Sleep 2
                $old_primary=$Primary
                Promote-Replica -Server_rep $Replicas -Primary $new_primary
                $Primary=$new_primary
                $Replicas = @()         
                Start-Sleep 3
        }
    }
    Start-Sleep -Seconds 1
}
