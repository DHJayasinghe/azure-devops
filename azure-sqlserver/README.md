### What's this script is about?
Your organization must have secured Azure SQL Server instance with public network access enabled, while allowing traffic to the server only for selected IP addresses. On this firewall rules, you must have set of firewall rules with static IP related to the organization known networks. But, when there are some users with dynamic public IP addresses, which should allow access to the server instance, you gonna face an adminstration problem on removing these addresses from firewall rules manually regularly. And also, if there is a Delete protection resource lock on the SQL server instance, you have to trouble yourself to remove this lock before removing those firewall rules.

### What's this script Do?
- Scan Azure SQL server instance firewall rules and remove existing firewall rules.
- Exclude removing firewall rules starts with certain prefix (ex: Firewall Rules with static IP ranges)
- Remove existing Delete protection resource lock on SQL Server instance before remove.
- Reset Delete protection resource lock on SQL Server instance after Script complete.
- Exclude removing Default firewall rule (AllowAllWindowsAzureIps).
- Able to provide multiple SQL Server instance names
- CI/CD friendly - Because this is a simple powershell script, this can be easily run on any CI/CD tool
