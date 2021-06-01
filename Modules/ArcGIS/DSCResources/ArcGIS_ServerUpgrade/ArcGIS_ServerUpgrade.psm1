<#
    .SYNOPSIS
        Resource to aid post upgrade completion workflows. This resource upgrades the Server Site once Server Installer has completed the upgrade.
    .PARAMETER Ensure
        Take the values Present or Absent. 
        - "Present" ensure Upgrade the Server Site once Server Installer is completed
        - "Absent" - (Not Implemented).
    .PARAMETER ServerHostName
        HostName of the Machine that is being Upgraded
    .PARAMETER Version
        Version to which the Server is being upgraded to
#>

function Get-TargetResource
{
	[CmdletBinding()]
	[OutputType([System.Collections.Hashtable])]
	param
	(
		[parameter(Mandatory = $true)]
		[System.String]
		$ServerHostName
	)
    
    Import-Module $PSScriptRoot\..\..\ArcGISUtility.psm1 -Verbose:$false

    $returnValue = @{
		ServerHostName = $ServerHostName
	}

	$returnValue
}

function Set-TargetResource
{
	[CmdletBinding()]
	param
	(
		[ValidateSet("Present","Absent")]
		[System.String]
        $Ensure,

        [parameter(Mandatory = $true)]
        [System.String]
        $ServerHostName,
    
        [parameter(Mandatory = $true)]
        [System.String]
        $Version

	)
    
    Import-Module $PSScriptRoot\..\..\ArcGISUtility.psm1 -Verbose:$false

    #$MachineFQDN = Get-FQDN $env:COMPUTERNAME    
    Write-Verbose "Fully Qualified Domain Name :- $ServerHostName"

    [System.Reflection.Assembly]::LoadWithPartialName("System.Web") | Out-Null
	Write-Verbose "Waiting for Server 'https://$($ServerHostName):6443/arcgis/admin'"
    Wait-ForUrl "https://$($ServerHostName):6443/arcgis/admin" -HttpMethod 'GET'

    if($Ensure -ieq 'Present') {        
        $Referer = "http://localhost"
        $ServerSiteURL = "https://$($ServerHostName):6443"
        [string]$ServerUpgradeUrl = $ServerSiteURL.TrimEnd('/') + "/arcgis/admin/upgrade"
        $Response = Invoke-ArcGISWebRequest -Url $ServerUpgradeUrl -HttpFormParameters @{f = 'json';runAsync='true'} -Referer $Referer -Verbose
                    
        Write-Verbose "Making request to $ServerUpgradeUrl to Upgrade the site"
        if($Response.upgradeStatus -ieq 'IN_PROGRESS') {
            Write-Verbose "Upgrade in Progress"
			$ServerReady = $false
			$Attempts = 0

            while(-not($ServerReady) -and ($Attempts -lt 60)){
                $ResponseStatus = Invoke-ArcGISWebRequest -Url $ServerUpgradeUrl -HttpFormParameters @{f = 'json'} -Referer $Referer -Verbose -HttpMethod 'GET'
                if(($ResponseStatus.upgradeStatus -ne 'IN_PROGRESS') -and ($ResponseStatus.code -ieq '404') -and ($ResponseStatus.status -ieq 'error')){
                    Write-Verbose "Server Upgrade is likely done!"
                    $Info = Invoke-ArcGISWebRequest -Url ($ServerSiteURL.TrimEnd('/') + "/arcgis/rest/info") -HttpFormParameters @{f = 'json';} -Referer $Referer -Verbose
                    $currentversion = "$($Info.currentVersion)"
					Write-Verbose "Current Version Installed - $currentversion"
                    if($currentversion -ieq "10.51"){
                        $currentversion = "10.5.1"
                    }elseif($currentversion -ieq "10.61"){
                        $currentversion = "10.6.1"
                    }elseif($currentversion -ieq "10.71"){
                        $currentversion = "10.7.1"
                    }elseif($currentversion -ieq "10.81"){
                        $currentversion = "10.8.1"
                    }
                    
                    if(($Version.Split('.').Length -gt 1) -and ($Version.Split('.')[1] -eq $currentversion.Split('.')[1])){
                        if($Version.Split('.').Length -eq 3){
                            if($Version.Split('.')[2] -eq $currentversion.Split('.')[2]){
                                Write-Verbose 'Server Upgrade Successful'
                                $ServerReady = $true
                                break
                            }
                        }else{
                            Write-Verbose 'Server Upgrade Successful'
                            $ServerReady = $true
                            break
                        }
                    }
                    
                }elseif(($ResponseStatus.status -ieq "error") -and ($ResponseStatus.code -ieq '500')){
					throw $ResponseStatus.messages
					break
				}elseif($ResponseStatus.upgradeStatus -ieq "LAST_ATTEMPT_FAILED"){
                    throw $ResponseStatus.messages
					break
                }
				Write-Verbose "Response received:- $(ConvertTo-Json -Depth 5 -Compress -InputObject $ResponseStatus)"  
				Start-Sleep -Seconds 30
				$Attempts = $Attempts + 1
            }
        }else{
			throw "Error:- $(ConvertTo-Json -Depth 5 -Compress -InputObject $Response)"  
		}
    }
    elseif($Ensure -ieq 'Absent') {
       Write-Verbose "Do Nothing"
    }
}

function Test-TargetResource
{
	[CmdletBinding()]
	[OutputType([System.Boolean])]
	param
	(
		[ValidateSet("Present","Absent")]
		[System.String]
        $Ensure,
        
        [parameter(Mandatory = $true)]
        [System.String]
        $ServerHostName,

        [parameter(Mandatory = $true)]
        [System.String]
        $Version
        
    )
    
    Import-Module $PSScriptRoot\..\..\ArcGISUtility.psm1 -Verbose:$false

    [System.Reflection.Assembly]::LoadWithPartialName("System.Web") | Out-Null

    $result = Test-Install -Name "Server" -Version $Version
    
    $Referer = "http://localhost"
    $ServerUpgradeUrl = "https://$($ServerHostName):6443/arcgis/admin/upgrade"
    $ResponseStatus = Invoke-ArcGISWebRequest -Url $ServerUpgradeUrl -HttpFormParameters @{f = 'json'} -Referer $Referer -Verbose -HttpMethod 'GET'
    
    if($result) {
        if($ResponseStatus.upgradeStatus -ieq "UPGRADE_REQUIRED" -or $ResponseStatus.upgradeStatus -ieq "LAST_ATTEMPT_FAILED" -or $ResponseStatus.upgradeStatus -ieq "IN_PROGRESS"){
            $result = $false
        }else{
            $result = $true
        }
    }else{
        throw "ArcGIS Server not upgraded to required Version"
    }
    
    
    if($Ensure -ieq 'Present') {
	       $result   
    }
    elseif($Ensure -ieq 'Absent') {        
        (-not($result))
    }
}

Export-ModuleMember -Function *-TargetResource