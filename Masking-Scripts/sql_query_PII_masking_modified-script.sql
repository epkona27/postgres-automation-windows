--script to Mask FirstName,Lastname,Phone number, Address, SSN, generate EMAIL from Firstname and Last
DROP TABLE IF EXISTS #staging_emp_cln1
select CAST(ROW_NUMBER() OVER(ORDER BY NEWID()) AS VARCHAR(10)) as RandomValue,FirstName, LastName into #staging_emp_cln1
FROM OPENROWSET(
BULK 'C:\Users\ADM90995\Downloads\sample_full_names.csv',
FORMAT = 'CSV',
FIRSTROW = 2 -- Skip header
)  WITH (
FirstName VARCHAR(100) 1, -- Maps to column 
LastName VARCHAR(100) 2
) AS csv_data;
DROP TABLE IF EXISTS #staging_emp_add_cln1
SELECT  CAST(ROW_NUMBER() OVER(ORDER BY NEWID()) AS VARCHAR(10)) as RandomValue , Address_1 into #staging_emp_add_cln1
FROM OPENROWSET(
BULK 'C:\Users\ADM90995\Downloads\addresses.set',
FORMAT = 'CSV',
FIRSTROW = 2 -- Skip header
)  WITH (
Address_1 VARCHAR(100) 1 -- Maps to column 
) as csv_data;
DROP TABLE IF EXISTS #staging_email_domain_cln1
SELECT  CAST(ROW_NUMBER() OVER(ORDER BY NEWID()) AS VARCHAR(10)) as RandomValue, Email_Domain into #staging_email_domain_cln1
FROM OPENROWSET(
BULK 'C:\Users\ADM90995\Downloads\free_email_domains.set',
FORMAT = 'CSV',
FIRSTROW = 2 -- Skip header
)  WITH (
Email_Domain VARCHAR(100) 1 -- Maps to column 
) as csv_data;
with target_CTE as (
select *, ROW_NUMBER() over (order by (select NULL)) as rn from [dbo].[EMPL_VIEW_CLN1]),
source_CTE as (
select *,ROW_NUMBER() over (order by (select NULL)) as rn from #staging_emp_cln1 ),
addr_CTE as (
select *,ROW_NUMBER() over (order by (select NULL)) as rn from #staging_emp_add_cln1),
email_CTE as (
select *,ROW_NUMBER() over (order by (select NULL)) as rn from #staging_email_domain_cln1),
cte_n1 (n) AS (SELECT 1 FROM (VALUES (1),(1),(1),(1),(1),(1),(1),(1),(1),(1)) n (n)), 
cte_n2 (n) AS (SELECT 1 FROM cte_n1 a CROSS JOIN cte_n1 b),     -- 100 rows
cte_n3 (n) AS (SELECT 1 FROM cte_n2 a CROSS JOIN cte_n2 b),     -- 10,000 rows
cte_Tally (n) AS (
    SELECT TOP 10000 -- set the number of row you wanr here...
        ROW_NUMBER() OVER (ORDER BY (SELECT NULL))
    FROM
        cte_n3 a CROSS JOIN cte_n3 b                            -- 100,000,000 rows
    )
--select S.FirstName,S.Lastname from target_CTE t join source_CTE S on t.rn = S.rn;
--select * from #staging_emp_add_cln1
update t
set t.[FRST_NM]=S.FirstName,
t.[LST_NM]=S.LastName,
t.addr_loc1=A.Address_1,
t.EMAIL=lOWER(CONCAT(TRIM(S.FirstName),'.',LEFT(TRIM(S.LastName),2),'@',TRIM(E.Email_Domain))),
t.mask_ssn = '' + STUFF(STUFF(pn.ssn, 4, 0, '-'), 7, 0, '-'),
t.MBL_PHN = '(' + STUFF(STUFF(pn1.PhoneNumber, 7, 0, '-'), 4, 0, ') ')
from target_CTE t join source_CTE S on t.rn = S.rn
join addr_CTE A on t.rn=A.rn
join email_CTE E on t.rn=E.rn
cross join cte_Tally CROSS APPLY ( VALUES (CAST(ABS(CHECKSUM(NEWID())) % 900000000 + 100000001 AS VARCHAR(10))) ) pn (ssn) 
CROSS APPLY ( VALUES (CAST(ABS(CHECKSUM(NEWID())) % 9999999999 + 1000000001 AS VARCHAR(14))) ) pn1 (PhoneNumber);
DROP TABLE #staging_emp_cln1;
DROP TABLE #staging_emp_add_cln1;
DROP TABLE #staging_email_domain_cln1;

------------

