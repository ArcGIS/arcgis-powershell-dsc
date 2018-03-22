<#
    .SYNOPSIS
        Configures the ArcGIS Portal for Disconnected Environment
    .PARAMETER Ensure
        Take the values Present or Absent. 
        - "Present" ensures that Portal is Configured for Disconnected-Use.
        - "Absent" ensures that Portal is Configured as out-of-the-box - Not Implemented.
    .PARAMETER HostName
        Host Name of the Machine on which the ArcGIS Portal is Installed
    .PARAMETER SiteAdministrator
        Credentials to access Server/Portal with admin privileges
    .PARAMETER DisableExternalContent
        Switch for Disabling External Content
    .PARAMETER DisableLivingAtlas
        Switch for Disabling Content of Living Atlas
    .PARAMETER LivingAtlasGroupIds
        GroupIds for the Living Atlas Contents
    .PARAMETER ConfigProperties
        JSON of Properties and their values in config.js
    .PARAMETER HelperServices
        Defines HelperServices which shoult be set on Portal
#>

function Get-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param
    (
        [ValidateSet("Present","Absent")]
        [System.String]
        $Ensure,

        [parameter(Mandatory = $true)]
        [System.String]
        $HostName,

        [parameter(Mandatory = $true)]
        [System.Management.Automation.PSCredential]
        $SiteAdministrator,

        [System.String]
        $ConfigJsPath,

        [System.Boolean]
        $DisableExternalContent = $false,

        [System.Boolean]
        $DisableLivingAtlas = $false,

        [System.Array]
        $LivingAtlasGroupIds,

        [System.String]
        $HelperServices
    )
    Import-Module $PSScriptRoot\..\..\ArcGISUtility.psm1 -Verbose:$false

    $null
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
        $HostName,

        [parameter(Mandatory = $true)]
        [System.Management.Automation.PSCredential]
        $SiteAdministrator,

        [System.String]
        $ConfigJsPath,

        [System.Boolean]
        $DisableExternalContent = $false,

        [System.Boolean]
        $DisableLivingAtlas = $false,

        [System.Array]
        $LivingAtlasGroupIds,

        [System.String]
        $HelperServices
    )
    #[System.Reflection.Assembly]::LoadWithPartialName("System.Web") | Out-Null
    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true} # Allow self-signed certificates
    Import-Module $PSScriptRoot\..\..\ArcGISUtility.psm1 -Verbose:$false

    Write-Verbose "Fully Qualified Domain Name :- $HostName" 
    $PortalUrl = "https://$($HostName):7443/arcgis"
    $ServiceRestartRequired = $false

    Wait-ForUrl -Url "$PortalUrl/portaladmin/" -LogFailures
    $token = Get-PortalToken -PortalHostName $HostName -Credential $SiteAdministrator -Referer "http://localhost"

    if ($DisableExternalContent) 
    {
        Set-ExternalContentEnabled -PortalUrl $PortalUrl -Token $($token.token)
    } else {
        Write-Verbose "Disconnected Environment DisableExternalContent set to false"
    }

    if ($DisableLivingAtlas) 
    {
        $lAStatus = Get-LivingAtlasStatus -PortalUrl $PortalUrl -Token $($token.token) -LivingAtlasGroupIds $LivingAtlasGroupIds
        if ($lAStatus -eq 'disableable')
        {
            Set-LivingAtlasDisabled -PortalUrl $PortalUrl -Token $($token.token) -LivingAtlasGroupIds $LivingAtlasGroupIds
            $lAStatus = Get-LivingAtlasStatus -PortalUrl $PortalUrl -Token $($token.token) -LivingAtlasGroupIds $LivingAtlasGroupIds
        }
        if ($lAStatus -eq 'disabled')
        {
            Write-Verbose "Living Atlas disabled"
        } else {
            Write-Verbose "Living Atlas cannot be disabled:- $lAStatus"
        }
    } else {
        Write-Verbose "Disconnected Environment DisableLivingAtlas set to false"
    }

    if ($ConfigJsPath)
    {
        $curConfigFilePath = Get-ConfigFilePath
        if ((Test-Path $ConfigJsPath) -and -not (Test-ConfigFiles -CurConfigFilePath $curConfigFilePath -NewConfigFilePath $ConfigJsPath))
        {
            Set-ConfigFile -ConfigFilePath $ConfigJsPath
            $ServiceRestartRequired = $true
        }
    }

    if ($HelperServices)
    {
        $HelperSrvcs = ConvertFrom-Json $HelperServices
        $CurHelperServices = Get-HelperServices -PortalUrl $PortalUrl -Token $($token.token)
        $helperServiceParams = @{}

        if($HelperSrvcs.geometry)
        {
            if ($HelperSrvcs.geometry.useHostedServer)
            {
                $HostedServerUrl = Get-HostedServerUrl -PortalUrl $PortalUrl -Token $($token.token)
                if ($HostedServerUrl)
                {
                    if (-not (Test-GeometryStatus -ServerUrl $HostedServerUrl -Token $($token.token)))
                    {
                        Set-GeometryStatus -ServerUrl $HostedServerUrl -Token $($token.token)
                    }

                    if (-not (Test-GeometrySharing -ServerUrl $HostedServerUrl -PortalUrl $PortalUrl -Token $($token.token)))
                    {
                        Set-GeometrySharing -ServerUrl $HostedServerUrl -PortalUrl $PortalUrl -Token $($token.token)
                    }
                    
                    if (-not ($CurHelperServices.geometry.url.StartsWith($HostedServerUrl)))
                    {
                        $serviceUrl = "$HostedServerUrl/rest/services/Utilities/Geometry/GeometryServer"
                        $helperServiceParams.Add("geometryService",  '{"url": "' + $serviceUrl + '" }')
                    }
                } else {
                    Write-Warning "No Hosted Server available. Geometry-Service is not working."
                }
            }
            elseif ($HelperSrvcs.geometry.url)
            {
                if ($HelperSrvcs.geometry.url -ne $CurHelperServices.geometry.url)
                {
                    $helperServiceParams.Add("geometryService",  '{"url": "' + $HelperSrvcs.geometry.url + '" }')
                }
            }
        }
        if ($helperServiceParams.Count -gt 0)
        {
            Set-HelperServices -PortalUrl $PortalUrl -Token $($token.token) -HelperServices (ConvertTo-Json $helperServiceParams)
        }
    }

    if ($ServiceRestartRequired)
    {
        Restart-PortalService
        Wait-ForUrl "$($PortalUrl)/portaladmin" -HttpMethod 'GET'
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
        $HostName,

        [System.Management.Automation.PSCredential]
        $SiteAdministrator,

        [System.String]
        $ConfigJsPath,

        [System.Boolean]
        $DisableExternalContent = $false,

        [System.Boolean]
        $DisableLivingAtlas = $false,

        [System.Array]
        $LivingAtlasGroupIds,

        [System.String]
        $HelperServices
    )
    #[System.Reflection.Assembly]::LoadWithPartialName("System.Web") | Out-Null
    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true} # Allow self-signed certificates
    Import-Module $PSScriptRoot\..\..\ArcGISUtility.psm1 -Verbose:$false

    $result = $true
    Write-Verbose "Fully Qualified Domain Name :- $HostName" 
    $PortalUrl = "https://$($HostName):7443/arcgis"

    Wait-ForUrl -Url "$PortalUrl/portaladmin/" -LogFailures
    $token = Get-PortalToken -PortalHostName $HostName -Credential $SiteAdministrator -Referer "http://localhost"

    if ($result -and $DisableExternalContent)
    {
        $result = Get-ExternalContentEnabled -PortalUrl $PortalUrl -Token $($token.token)
    }

    if ($result -and $DisableLivingAtlas)
    {
        $lAStatus = Get-LivingAtlasStatus -PortalUrl $PortalUrl -Token $($token.token) -LivingAtlasGroupIds $LivingAtlasGroupIds
        if ($lAStatus -eq 'disabled')
        {
            Write-Verbose "Living Atlas already disabled."
        } else {
            Write-Verbose "Status of Living Atlas:- $lAStatus"
            $result = $false
        }
    }

    if ($result -and $ConfigJsPath)
    {
        $ConfigFilePath = Get-ConfigFilePath

        if (Test-Path $ConfigJsPath)
        {
            $result = Test-ConfigFiles -CurConfigFilePath $ConfigFilePath -NewConfigFilePath $ConfigJsPath
        }
        else
        {
            Write-Verbose "ERROR: Config.js-File is not readable:- $ConfigJsPath"
        }
    }

    if ($result -and $HelperServices)
    {
        $HelperSrvcs = ConvertFrom-Json $HelperServices
        $CurHelperServices = Get-HelperServices -PortalUrl $PortalUrl -Token $($token.token)

        if($result -and ($HelperSrvcs.geometry))
        {
            if ($HelperSrvcs.geometry.useHostedServer)
            {
                $HostedServerUrl = Get-HostedServerUrl -PortalUrl $PortalUrl -Token $($token.token)
                if ($result -and -not ($HostedServerUrl))
                {
                    Write-Warning "No Hosted Server available. Geometry-Service is not working."
                    $result = $false
                }
                
                if ($result -and -not ($CurHelperServices.geometry.url.StartsWith($HostedServerUrl)))
                {
                    Write-Verbose "Current Geometry-Service $($CurHelperServices.geometry.url) does not match Hosted-Server $HostedServerUrl"
                    $result = $false
                }

                if ($result -and -not (Test-GeometryStatus -ServerUrl $HostedServerUrl -Token $($token.token)))
                {
                    Write-Verbose "Geometry-Service on Hosted-Server not running"
                    $result = $false
                }

                if ($result -and -not (Test-GeometrySharing -ServerUrl $HostedServerUrl -PortalUrl $PortalUrl -Token $($token.token)))
                {
                    Write-Verbose "Geometry-Service is not shared to Everyone"
                    $result = $false
                }
            }
            elseif ($HelperSrvcs.geometry.url)
            {
                if ($HelperSrvcs.geometry.url -ne $CurHelperServices.geometry.url)
                {
                    Write-Verbose "Current Geometry-Service: $($CurHelperServices.geometry.url) does not match configured Url $($HelperSrvcs.geometry.url)"
                    $result = $false
                }
            }
        }
    }
    
    $result
}

function Test-GeometrySharing
{
    [CmdletBinding()]
    param(
        [System.String]
        $ServerUrl,

        [System.String]
        $PortalUrl,

        [System.String]
        $Token,

        [System.String]
        $Referer = 'http://localhost'
    )

    $geometryService = Invoke-ArcGISWebRequest -Url "$ServerUrl/admin/services/Utilities/Geometry.GeometryServer" `
                    -HttpFormParameters @{ f = 'json'; token = $Token; } -Referer $Referer -HttpMethod 'GET'

    $portalItemId = $geometryService.portalProperties.portalItems[0].itemId

    $result = Test-PortalItemSharing -PortalUrl $PortalUrl -Token $Token -PortalItemId $portalItemId

    $result
}

function Set-GeometrySharing
{
    [CmdletBinding()]
    param(
        [System.String]
        $ServerUrl,

        [System.String]
        $PortalUrl,

        [System.String]
        $Token,

        [System.String]
        $Referer = 'http://localhost'


    )

    $geometryService = Invoke-ArcGISWebRequest -Url "$ServerUrl/admin/services/Utilities/Geometry.GeometryServer" `
                    -HttpFormParameters @{ f = 'json'; token = $Token; } -Referer $Referer -HttpMethod 'GET'

    $portalItemId = $geometryService.portalProperties.portalItems[0].itemId
    $sharingParams = '{ "everyone": "true" }'

    Set-PortalItemSharing -PortalUrl $PortalUrl -Token $Token -PortalItemId $portalItemId -SharingParams $sharingParams
}

function Test-PortalItemSharing
{
    [CmdletBinding()]
    param(
        [System.String]
        $PortalUrl,

        [System.String]
        $Token,

        [System.String]
        $Referer = 'http://localhost',

        [System.String]
        $PortalItemId
    )

    $result = $false
    $portalItem = Invoke-ArcGISWebRequest -Url "$PortalUrl/sharing/rest/content/items/$PortalItemId" `
                    -HttpFormParameters @{ f = 'json'; token = $Token; } -Referer $Referer -HttpMethod 'GET'

    if ($portalItem.access -ieq "public")
    {
        $result = $true
    }
    $result
}

function Set-PortalItemSharing
{
    [CmdletBinding()]
    param(
        [System.String]
        $PortalUrl,

        [System.String]
        $Token,

        [System.String]
        $Referer = 'http://localhost',

        [System.String]
        $PortalItemId,

        [System.String]
        $SharingParams
    )

    $params =  @{ f = 'json'; token = $Token; }
    $shareParams = ConvertFrom-Json $SharingParams
    ForEach ($param in $shareParams.PSObject.Properties)
    {
        $params.Add($param.Name, $param.Value)
    }
    Write-Verbose "Sharing PortalItem:- $PortalItemId, $shareParams"
    Invoke-ArcGISWebRequest -Url "$PortalUrl/sharing/rest/content/items/$PortalItemId/share" -HttpFormParameters $params -Referer $Referer
}

function Test-GeometryStatus
{
    [CmdletBinding()]
    param(
        [System.String]
        $ServerUrl,

        [System.String]
        $Token,

        [System.String]
        $Referer = 'http://localhost'
    )

    $result = $false
    $status = Invoke-ArcGISWebRequest -Url "$ServerUrl/admin/services/Utilities/Geometry.GeometryServer/status" `
                    -HttpFormParameters @{ f = 'json'; token = $Token; } -Referer $Referer -HttpMethod 'GET'

    if (($status.configuredState -eq "STARTED") -and ($status.realTimeState -eq "STARTED"))
    {
        $result = $true
    }
    $result
}

function Set-GeometryStatus
{
    [CmdletBinding()]
    param(
        [System.String]
        $ServerUrl,

        [System.String]
        $Token,

        [System.String]
        $Referer = 'http://localhost',

        [System.String]
        $Status = "STARTED"
    )

    if ($Status -eq "STARTED")
    {
        Write-Verbose "Starting Geometry-Service"
        $resp = Invoke-ArcGISWebRequest -Url "$ServerUrl/admin/services/Utilities/Geometry.GeometryServer/start" `
                    -HttpFormParameters @{ f = 'json'; token = $Token; } -Referer $Referer -TimeOutSec 300 -LogResponse
        Write-Verbose "Response:- $resp"
    } else {
        Invoke-ArcGISWebRequest -Url "$ServerUrl/admin/services/Utilities/Geometry.GeometryServer/stop" `
                    -HttpFormParameters @{ f = 'json'; token = $Token; } -Referer $Referer -TimeOutSec 300
    }
}

function Get-HelperServices
{
    [CmdletBinding()]
    param(
        [System.String]
        $PortalUrl,

        [System.String]
        $Token,

        [System.String]
        $Referer = 'http://localhost'
    )

    $result = $false
    $portalsSelf = Invoke-ArcGISWebRequest -Url "$PortalUrl/sharing/rest/portals/self" `
                    -HttpFormParameters @{ f = 'json'; token = $Token; } -Referer $Referer -HttpMethod 'GET'

    $portalsSelf.helperServices
}

function Set-HelperServices
{
    [CmdletBinding()]
    param(
        [System.String]
        $PortalUrl,

        [System.String]
        $Token,

        [System.String]
        $Referer = 'http://localhost',

        [System.String]
        $HelperServices
    )

    $params =  @{ f = 'json'; token = $Token; }
    $helperSrvcs = ConvertFrom-Json $HelperServices
    ForEach ($service in $helperSrvcs.PSObject.Properties)
    {
        $params.Add($service.Name, $service.Value)
    }
    
    Write-Verbose "Set HelperServices:- $HelperServices"
    $resp = Invoke-ArcGISWebRequest -Url "$PortalUrl/sharing/rest/portals/self/update" -HttpFormParameters $params -Referer $Referer

    Write-Verbose "Response:- $resp"
}

function Get-HostedServerUrl
{
    [CmdletBinding()]
    param(
        [System.String]
        $PortalUrl,

        [System.String]
        $Token,

        [System.String]
        $Referer = 'http://localhost'
    )

    $result = $false
    $servers = Invoke-ArcGISWebRequest -Url "$PortalUrl/portaladmin/federation/servers" `
                    -HttpFormParameters @{ f = 'json'; token = $Token; } -Referer $Referer -HttpMethod 'GET'

    ForEach ($server in $servers.servers)
    {
        if ($server.isHosted)
        {
            $result = $server.adminUrl
            break
        }
    }

    $result
}

function Get-ConfigFilePath
{
    $regKey = Get-EsriRegistryKeyForService -ServiceName 'Portal for ArcGIS'
    $installDir = (Get-ItemProperty -Path $regKey -ErrorAction Ignore).InstallDir
    
    $configFilePath = Join-Path $installDir "webapps\arcgis#home\js\arcgisonline\config.js"
    
    $configFilePath
}

function Test-ConfigFiles
{
    [CmdletBinding()]
    param(
        [System.String]
        $CurConfigFilePath,

        [System.String]
        $NewConfigFilePath
    )

    if ((Get-FileHash $CurConfigFilePath).hash -ne (Get-FileHash $NewConfigFilePath).hash)
    {
        Write-Verbose "Config.js-Files are different"
        $false
    }
    else 
    {
        Write-Verbose "Config.js-Files are equal"
        $true
    }
}

function Set-ConfigFile
{
    param
    (
        [System.String]
        $ConfigFilePath
    )

    Write-Verbose "Copying Config.js $ConfigFilePath to Portal."
    $regKey = Get-EsriRegistryKeyForService -ServiceName 'Portal for ArcGIS'
    $installDir = (Get-ItemProperty -Path $regKey -ErrorAction Ignore).InstallDir
    $version = (Get-ItemProperty -Path $RegKey -ErrorAction Ignore).RealVersion
    if ($version.Split('.').Count -lt 3)
    {
        $version += '.0'
    }
    $customConfigFilePath = Join-Path $installDir "customizations\$version\webapps\arcgis#home\js\arcgisonline\config.js"
    Copy-Item -Path $ConfigFilePath -Destination $customConfigFilePath -Force
}

function Restart-PortalService {
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [System.String]
        $ServiceName = 'Portal for ArcGIS'
    )

    try {
        Write-Verbose "Restarting Service $ServiceName"
        Stop-Service -Name $ServiceName -Force -ErrorAction Ignore
        Write-Verbose 'Stopping the service'
        Wait-ForServiceToReachDesiredState -ServiceName $ServiceName -DesiredState 'Stopped'
        Write-Verbose 'Stopped the service'
    }
    catch {
        Write-Verbose "[WARNING] Stopping Service $_"
    }

    try {
        Write-Verbose 'Starting the service'
        Start-Service -Name $ServiceName -ErrorAction Ignore
        Wait-ForServiceToReachDesiredState -ServiceName $ServiceName -DesiredState 'Running'
        Write-Verbose "Restarted Service '$ServiceName'"
    }
    catch {
        Write-Verbose "[WARNING] Starting Service $_"
    }
}


function Get-ExternalContentEnabled 
{
    [CmdletBinding()]
    param(
        [System.String]
        $PortalUrl,

        [System.String]
        $Token,

        [System.String]
        $Referer = 'http://localhost'
    )

    $configuration = Invoke-ArcGISWebRequest -Url "$PortalUrl/portaladmin/system/content/configuration" `
                    -HttpFormParameters @{ f = 'json'; token = $Token; } -Referer $Referer -HttpMethod 'GET'

    if ($configuration.isExternalContentEnabled -or $configuration.error) {
        $false
    } else {
        $true
    }

}

function Set-ExternalContentEnabled 
{
    [CmdletBinding()]
    param(
        [System.String]
        $PortalUrl,

        [System.String]
        $Token,

        [System.String]
        $Referer = 'http://localhost'
    )
    $result = $true

    if(-not(Get-ExternalContentEnabled -PortalUrl $PortalUrl -Token $Token -Referer $Referer))
    {
        # updating content configuration requires reindexing which may take up to a few minutes > timeout 600
        $configuration = Invoke-ArcGISWebRequest -Url "$PortalUrl/portaladmin/system/content/configuration/update" `
                        -HttpFormParameters @{ f = 'json'; token = $Token; externalContentEnabled = 'false'} -Referer $Referer `
                        -TimeOutSec 600 -HttpMethod 'POST'
        
        Write-Verbose "External Content disabled:- $configuration"
        $result = if($configuration.status -match "success") {$true} else {$false}
    } else {
        Write-Verbose "External Content already disabled in /portaladmin/system/content/configuration - skipping"
        $result = $true
    }
    $result
}

function Get-LivingAtlasGroupsStatus
{
    [CmdletBinding()]
    param(
        [System.String]
        $PortalUrl,

        [System.String]
        $Token,

        [System.String]
        $Referer = 'http://localhost',

        [System.Array]
        $LivingAtlasGroupIds
    )

    $result = @{}
    ForEach ($groupId in $LivingAtlasGroupIds)
    {
        $resp = Invoke-ArcGISWebRequest -Url "$PortalUrl/portaladmin/system/content/livingatlas/status" `
                                -HttpFormParameters @{ f = 'json'; token = $Token; groupId = $groupId } -Referer $Referer -LogResponse
        $result += @{ $groupId = $resp}
    }

    $result
}

function Get-LivingAtlasStatus
{
    [CmdletBinding()]
    param(
        [System.String]
        $PortalUrl,

        [System.String]
        $Token,

        [System.String]
        $Referer = 'http://localhost',

        [System.Array]
        $LivingAtlasGroupIds
    )

    $result = "disabled"

    $groupsStatus = Get-LivingAtlasGroupsStatus -PortalUrl $PortalUrl -Token $Token -LivingAtlasGroupIds $LivingAtlasGroupIds
    
    ForEach ($status in $groupsStatus.GetEnumerator())
    {
        if ($status.Value.error)
        {
            $result = "Error in LivingAtlas:- $($status.Name) > $($status.Value.error)"
            break
        }
        elseif ($result.StartsWith('disable') -and `
                    (-not $status.Value.subscriberContentEnabled -and `
                    -not $status.Value.premiumContentEnabled -and `
                    -not $status.Value.subscriberContentShared -and `
                    -not $status.Value.premiumContentShared))
        {
            if ($status.Value.publicContentEnabled -or $status.Value.publicContentShared)
            {
                $result = 'disableable'
            }
        } else {
            $result = "additional Living Atlas Content enabled/shared:- $($status.Name) > $($status.Value)"
            break
        }
    }

    $result
}

function Set-LivingAtlasDisabled
{
    [CmdletBinding()]
    param(
        [System.String]
        $PortalUrl,

        [System.String]
        $Token,

        [System.String]
        $Referer = 'http://localhost',

        [System.Array]
        $LivingAtlasGroupIds
    )
    $result = $true

    ForEach ($groupId in $LivingAtlasGroupIds)
    {
        $resp = Invoke-ArcGISWebRequest -Url "$PortalUrl/portaladmin/system/content/livingatlas/unshare" `
                        -HttpFormParameters @{ f = 'json'; token = $Token; groupId = $groupId; type = "Public";} -Referer $Referer -TimeOutSec 600
        if ($resp.error)
        {
            Write-Host "Unshare Living Atlas Group $($groupId) gives Error:- $($resp.error)"
            $result = $false
            break
        }
    }
    $result
}

Export-ModuleMember -Function *-TargetResource


