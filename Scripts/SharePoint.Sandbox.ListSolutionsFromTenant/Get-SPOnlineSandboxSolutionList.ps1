<#
.SYNOPSIS
Can be used to scan sandbox solutions within SharePoint Online tenant. Lists site templates, custom sandbox solutions and InfoPath forms with code behind.

.EXAMPLE
PS C:\> .\Get-SPOnlineSandboxSolutionList.ps1 -AdminUrl https://contoso-admin.sharepoint.com

.EXAMPLE
PS C:\> $creds = Get-Credential
PS C:\> .\Get-SPOnlineSandboxSolutionList.ps1 -AdminUrl https://contoso-admin.sharepoint.com -Credentials $creds

#>
[CmdletBinding()]
param
(
    [Parameter(Mandatory = $true, HelpMessage="Enter the URL of the target admin site collection , e.g. 'https://contoso-admin.sharepoint.com'")]
    [String]
    $AdminUrl,

    [Parameter(Mandatory = $false, HelpMessage="Optional administration credentials to SPO tenant. Notice that you need to use tenant admin credentials for this.")]
    [PSCredential]
    $Credentials,
	
	[Parameter(Mandatory = $false, HelpMessage="Optional custom delimiter character to use for CSV output.")]
    [char]
    $Delimiter = ','
)

# Get reference to SPO CSOM assemblies - SPO SDK or SPO PowerShell CmdLet's will need to be installed on this machine
Add-Type -Path (Resolve-Path "$env:CommonProgramFiles\microsoft shared\Web Server Extensions\16\ISAPI\Microsoft.SharePoint.Client.dll")
Add-Type -Path (Resolve-Path "$env:CommonProgramFiles\microsoft shared\Web Server Extensions\16\ISAPI\Microsoft.SharePoint.Client.Runtime.dll")

# Log file for output with the current time
$date = Get-Date
$logfile = ((Get-Item -Path ".\" -Verbose).FullName + "\SandboxReport_" + $date.ToFileTime() + ".csv")

Write-Host -ForegroundColor White "---------------------------------------------------------------------------"
Write-Host -ForegroundColor White "|               Get List of Sandbox solutions from tenant                 |"
Write-Host -ForegroundColor White "---------------------------------------------------------------------------"

Write-Host -ForegroundColor Yellow "Admin Site URL: $AdminUrl"
Write-Host ""
Write-Host ""

# Get credentials, if they were not provided
if($Credentials -eq $null)
{
	$Credentials = Get-Credential -Message "Enter Admin Credentials"
}

#Retrieve all site collection infos
Connect-SPOService -Url $AdminUrl -Credential $Credentials
# Note. this does not get site collections from recycle bins or OneDrive for Business sites
$sites = Microsoft.Online.SharePoint.PowerShell\Get-SPOSite -Limit All
# Counter for the progress tracking
$count = 1

# Write headers to output CSV report
$columHeaders = @(  "SiteURL", 
					"WSPName",
					"Author",
					"CreatedDate",
					"Activated",
					"HasAssemblies",
					"SolutionHash"
				)

Add-Content $logfile ([string]::Join($Delimiter, $columHeaders))

# Scan through the sites and output content from solution gallery (exists in root site of site collection)
foreach ($site in $sites)
{
	try 
	{
        # Connect to root web
        $context = New-Object Microsoft.SharePoint.Client.ClientContext($site.Url)  
        $creds = New-Object Microsoft.SharePoint.Client.SharePointOnlineCredentials($Credentials.UserName, $Credentials.Password) 
        $context.Credentials = $creds 

        $query = [Microsoft.SharePoint.Client.CamlQuery]::CreateAllItemsQuery()
		# Get the sandboxed solution gallery - Catalog code 121
		# Get items from the solution gallery
        $items = $context.Web.GetCatalog(121).GetItems($query)
        $context.Load($items)
        $context.ExecuteQuery()

		if ($items.Count -gt 0)
		{
            #List the sandbox solutions
            foreach ($item in $items)
            {  
				# Resolve status of the solution - 1=Activate, 0=not active
				$statusField = $item["Status"]
				if ($statusField)
				{
					$status = 1
				} else 
				{
					$status = 0
				}
				$hasAssembly = 0
				$metaInfoFields = $item["MetaInfo"].Split("`r`n")
				foreach ($metaInfoField in $metaInfoFields)
				{
					if ($metaInfoField.Contains("SolutionHasAssemblies"))
					{
						if ($metaInfoField.Contains("1")) 
						{
							$hasAssembly = 1
						}
						break;     
					}
				}
				
				$properties = @( $site.Url, 
								$item["FileLeafRef"].ToString(), 
								$item["Author"].LookupValue.Replace(",", ""), 
								$item["Created"], 
								$status, 
								$hasAssembly,
								$item["SolutionHash"] 
							  )

				# Output to console
				[string]$rowOutput = [string]::Join($Delimiter, $properties)
				
				Write-Host $rowOutput
				
				# Output report in format, which can be imported to excel
				Add-Content $logfile $rowOutput
			}
        }
        # Output to file right next to script location
        Write-Progress -Activity "Scanning site collections" -Status $site.Url -PercentComplete ($count / $sites.Count*100)
        # Tracking progress
        $count = $count + 1
    }
	catch
	{
        # Possible public site exception handler
        if ($site.Url -notlike "*public.*")
        {
            Write-Host -ForegroundColor Red "Exception occurred!" 
            Write-Host -ForegroundColor Red "Exception Type: $($_.Exception.GetType().FullName)"
            Write-Host -ForegroundColor Red "Exception Message: $($_.Exception.Message)"
        }
	}
	finally
	{
		if ($context -ne $null)
		{
			$context.Dispose()
		}
	}
}

Write-Host ""
Write-Host ""

Write-Host -ForegroundColor White "----------------------------------------------"
Write-Host -ForegroundColor White "|               List produced                |"
Write-Host -ForegroundColor White "----------------------------------------------"

Write-Host -ForegroundColor Yellow "Next steps: Import output file generated folder with ps1 to excel for analyses"
Write-Host -ForegroundColor Yellow "Columns are: Site URL, Sandbox solution name, Author, Created date, Solution is active, Solution has DLLs, unique has of the solution"