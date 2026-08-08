#$Nodes = @("10.0.126.118","10.0.126.119","10.0.126.92")

$Cluster = foreach($Node in $Nodes)
{
    try
    {
        $Role = psql `
            -h $Node `
            -U postgres `
            -d postgres `
            -t -A `
            -c "SELECT pg_is_in_recovery();"

        [PSCustomObject]@{
            Node = $Node
            Role = if($Role.Trim() -eq "f"){"Primary"}else{"Replica"}
        }
    }
    catch
    {
        [PSCustomObject]@{
            Node = $Node
            Role = "Unavailable"
        }
    }
}

$Cluster | Format-Table -AutoSize