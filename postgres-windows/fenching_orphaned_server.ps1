Invoke-Command -ComputerName pg01 {

    Stop-Service postgresql-x64-16 -Force
}