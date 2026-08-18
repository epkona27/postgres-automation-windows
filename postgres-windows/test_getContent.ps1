##test get-content and replace


#$postgresConf = "S:\Postgres\18.3\data\postgresql_test.conf"
#(Get-Content $postgresConf) |  ForEach-Object { $_ -replace "^primary_slot_name.*$","#primary_slot_name ='test123'" } | Set-Content $postgresConf


#$postgresConf = "S:\Postgres\18.3\data\postgresql_test1.conf"
#(Get-Content $postgresConf) |  ForEach-Object { $_ -replace "^#primary_slot_name.*$","primary_slot_name ='test123'" } | Set-Content $postgresConf


#$postgresConf = "S:\Postgres\18.3\data\postgresql_test.conf"
#(Get-Content $postgresConf) -replace '^primary_slot_name.*$', "#primary_slot_name ='test123'" | Set-Content $postgresConf


#$postgresConf = "S:\Postgres\18.3\data\postgresql_test1.conf"
#(Get-Content $postgresConf) -replace '^#primary_slot_name.*$',"cccccbjtudueccunhektrvidfruvlhnhfbirnuitbvgu
#" | Set-Content $postgresConf


#^(.*primary_slot_name.*)$', '#$1'/////   "^(?!\s*#)(?=.*YOUR_SEARCH_STRING)", "#"
#$postgresConf = "S:\Postgres\18.3\data\postgresql_test1.conf"
#(Get-Content $postgresConf) -replace '^(\s*)(primary_slot_name\s*=.*)$', '$1#$2' | Set-Content $postgresConf

#comment
#'^(\s*)(primary_slot_name\s*=.*)$', '$1# $2'

#uncomment
#'^(\s*)#\s*(primary_slot_name\s*=.*)$', '$1$2'

#^(.*primary_slot_name.*)$', '#$1'/////   "^(?!\s*#)(?=.*YOUR_SEARCH_STRING)", "#"
$postgresConf = "S:\Postgres\18.3\data\postgresql_test1.conf"
(Get-Content $postgresConf) -replace '^(\s*)#\s*(primary_slot_name\s*=.*)$', '$1$2' | Set-Content $postgresConf
