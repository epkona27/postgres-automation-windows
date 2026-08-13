try
{
    Test-SplitBrain

    Fence-Primary

    Promote-Standby

    Create-ReplicationSlots

    Reconfigure-Replicas

    Validate-Cluster

    Send-Alert "Failover Successful"
}
catch
{
    Send-Alert "Failover Failed"

    Rollback-Failover
}
