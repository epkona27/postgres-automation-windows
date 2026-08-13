function Promote-Replica
{
    param($Server)

    Invoke-Command `
      -ComputerName $Server `
      -ScriptBlock {

        & "C:\Program Files\PostgreSQL\18\bin\pg_ctl.exe" `
          promote `
          -D "D:\PostgreSQL\data"
    }

    Start-Sleep 15

    $Role = psql `
      -h $Server `
      -U postgres `
      -t `
      -c "SELECT pg_is_in_recovery();"

    if($Role.Trim() -eq "t")
    {
        throw "Promotion failed"
    }

    Write-Host "$Server promoted successfully"
}