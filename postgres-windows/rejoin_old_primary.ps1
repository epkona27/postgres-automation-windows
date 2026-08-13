Invoke-Command `
    -ComputerName $OldPrimary `
    -ArgumentList $NewPrimary,$ReplUser,$ReplPassword,$ServiceName `
    -ScriptBlock {

    param(
        $Primary,
        $User,
        $Password,
        $Svc
    )

    $DataDir = "D:\PostgreSQL\data"

    Stop-Service $Svc

    pg_rewind `
       --target-pgdata=$DataDir `
       --source-server="host=$Primary port=5432 user=postgres dbname=postgres" `
       --progress

    if ($LASTEXITCODE -ne 0)
    {
        throw "pg_rewind failed"
    }

    New-Item `
       -ItemType File `
       -Path "$DataDir\standby.signal" `
       -Force

    Add-Content `
      "$DataDir\postgresql.auto.conf" `
      "primary_conninfo = 'host=$Primary port=5432 user=$User password=$Password'"

    Start-Service $Svc
}