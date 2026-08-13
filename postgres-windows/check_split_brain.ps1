function Get-PgPrimaryReplicas
{
    param(
        [string[]]$Nodes,
        [string]$Database = "postgres",
        [string]$User = "postgres",
        [int]$Port = 5432
    )

    $Primaries = @()
    $Replicas=@()

    foreach ($Node in $Nodes)
    {
        try
        {
            $Role = psql `
                -h $Node `
                -U postgres `
                -d postgres `
                -t -A `
                -c "SELECT pg_is_in_recovery();" 2>$null

            if ($Role.Trim() -eq "f")
            {
                $Primaries += $Node
            }
	        else
	        {
		    $Replicas += $Node
		    }
	
        }
        catch {}
    }

    switch ($Primaries.Count)
    {
        0 {
            throw "No primary detected."
        }
        1 {
            return $Primaries[0], $Replicas
        }
        default {
            throw "Split-brain detected. Multiple primaries found: $($Primaries -join ', ')"
        }
    }
}