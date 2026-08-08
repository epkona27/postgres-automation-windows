function Get-PostgresPrimary
{
    param(
        [string[]]$Nodes,
        [string]$Database = "postgres",
        [string]$User = "postgres",
        [int]$Port = 5432
    )

    $Primaries = @()

    foreach($Node in $Nodes)
    {
        try
        {
            $Result = psql `
                -h $Node `
                -U $User `
                -d $Database `
                -p $Port `
                -t -A `
                -c "SELECT pg_is_in_recovery();" 2>$null

            if($Result.Trim() -eq "f")
            {
                $Primaries += $Node
            }
        }
        catch
        {
            Write-Warning "$Node unavailable"
        }
    }

    switch($Primaries.Count)
    {
        0 {
            throw "No primary found"
        }
        1 {
            return $Primaries[0]
        }
        default {
            throw "Split-brain detected: $($Primaries -join ', ')"
        }
    }
}