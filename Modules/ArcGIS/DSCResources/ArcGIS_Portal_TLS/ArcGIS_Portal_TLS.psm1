<#
    .SYNOPSIS
        Creates a SelfSigned Certificate or Installs a SSL Certificated Provided and Configures it with Portal.
    .PARAMETER Ensure
        Ensure makes sure that a Portal site is configured and joined to site if specified. Take the values Present or Absent. 
        - "Present" ensures the certificate is installed and configured with the portal.
        - "Absent" ensures the certificate configured with the portal is uninstalled and deleted(Not Implemented).
    .PARAMETER SiteName
        Site Name or Default Context of Portal
    .PARAMETER SiteAdministrator
        A MSFT_Credential Object - Primary Site Administrator.
    .PARAMETER CertificateFileLocation
        Certificate Path from where to fetch the certificate to be installed.
    .PARAMETER CertificatePassword
        Sercret Certificate Password or Key.
    .PARAMETER CName
        CName with which the Certificate will be associated.
    .PARAMETER PortalEndPoint
        Portal Endpoint with which the Certificate will be associated.
	.PARAMETER ServerEndPoint
        Not sure - Adds a Host Mapping of Server Machine and associates it with the certificate being Installed.
    .PARAMETER SslRootOrIntermediate
        List of RootOrIntermediate Certificates
#>

function Get-TargetResource
{
	[CmdletBinding()]
	[OutputType([System.Collections.Hashtable])]
	param
	(
		[parameter(Mandatory = $true)]
		[System.String]
		$SiteName
	)

	Import-Module $PSScriptRoot\..\..\ArcGISUtility.psm1 -Verbose:$false

	$null 
}

function Set-TargetResource
{
	[CmdletBinding()]
	param
	(
		[parameter(Mandatory = $true)]
		[System.String]
		$SiteName,

		[ValidateSet("Present","Absent")]
		[System.String]
		$Ensure,

		[System.Management.Automation.PSCredential]
		$SiteAdministrator,
		
		[System.String]
		$CertificateFileLocation,

		[System.String]
		$CertificatePassword,

        [System.String]
		$CName,

		[System.String]
		$PortalEndPoint,

		[System.String]
		$ServerEndPoint,

        [System.String]
        $SslRootOrIntermediate
	)

	Import-Module $PSScriptRoot\..\..\ArcGISUtility.psm1 -Verbose:$false

	if($ServerEndPoint -and ($ServerEndPoint -as [ipaddress])) {
		Write-Verbose "Adding Host mapping for $ServerEndPoint"
		Add-HostMapping -hostname $ServerEndPoint -ipaddress $ServerEndPoint        
	}
	elseif($CName -as [ipaddress]) {
		Write-Verbose "Adding Host mapping for $CName"
		Add-HostMapping -hostname $CName -ipaddress $CName        
	}

    if($CertificateFileLocation -and (Test-Path $CertificateFileLocation)) 
	{
		[System.Reflection.Assembly]::LoadWithPartialName("System.Web") | Out-Null
		$result = $false
		$MachineEndPoint = if($PortalEndPoint) { $PortalEndPoint} else { $env:COMPUTERNAME }
	    $FQDN = $MachineEndPoint
        if($FQDN.IndexOf('.') -lt 0) {
            $FQDN = Get-FQDN $MachineEndPoint
        }
        $PortalUrl = "https://$($FQDN):7443"  
        $PortalAdminUrl = "$($PortalUrl)/$SiteName/portaladmin/"
		$Referer = $PortalUrl
		try{
			Wait-ForUrl "https://$($FQDN):7443/$SiteName/sharing/rest/generateToken"
			$token = Get-PortalToken -PortalHostName $FQDN -SiteName $SiteName -Credential $SiteAdministrator -Referer $Referer 
		}catch{
			throw "[WARNING] Unable to get token:- $_"
		}
		if(-not($token.token)){
			throw "Unable to retrieve Portal Token for '$($PortalAdministrator.UserName)'"
		}else{
            Write-Verbose "Retrieved Portal Token"
		}
		try{
		    $certsConfig = Get-SSLCertificatesForPortal -PortalHostName $FQDN -SiteName $SiteName -Token $token.token -Referer $Referer
        }catch{
            throw "[WARNING] Unable to get SSL-CertificatesForPortal:- $_"
        }
		Write-Verbose "Current Alias for SSL Certificate:- '$($certsConfig.webServerCertificateAlias)' Certificates:- '$($certsConfig.sslCertificates -join ',')'"

        $ImportExistingCertFlag = $False
        $DeleteTempCert = $False
		if(-not($certsConfig.sslCertificates -icontains $CName)){
			Write-Verbose "Importing SSL Certificate with alias $CName"
			$ImportExistingCertFlag = $True
		}else{
            Write-Verbose "SSL Certificate with alias $CName already exists"
            $certConfig = Get-SSLCertificatesForPortal -PortalHostName $FQDN -SiteName $SiteName -Token $token.token -Referer $Referer -CName $CName
            if($CertificateFileLocation -and $CertificatePassword) {
                Write-Verbose "Examine certificate from $CertificateFileLocation"
                $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
                $cert.Import($CertificateFileLocation, $CertificatePassword, 'DefaultKeySet')
                $NewCertThumbprint = $cert.Thumbprint
                Write-Verbose "Thumbprint for the supplied certificate is $NewCertThumbprint"
                if($certConfig.sha1Fingerprint -ine $NewCertThumbprint){
                    $ImportExistingCertFlag = $True
                    Write-Verbose "Importing exsting certificate with alias $($CName)-temp"
                    try{
                        Import-ExistingCertificate -PortalHostName $FQDN -SiteName $SiteName -Token $token.token `
                            -Referer $Referer -CertAlias "$($CName)-temp" -CertificateFilePath $CertificateFileLocation -CertificatePassword $CertificatePassword
                        $DeleteTempCert = $True
                    }catch{
                        throw "[WARNING] Error Import-ExistingCertificate:- $_"
                    }

					try{
                        Update-PortalSSLCertificate -PortalHostName $FQDN -SiteName $SiteName -Token $token.token -Referer $Referer -CertAlias "$($CName)-temp"
						Write-Verbose "Updating to a temp SSL Certificate causes the web server to restart asynchronously. Waiting 180 seconds before checking for intitialization"
                        Start-Sleep -Seconds 180
                        Wait-ForUrl -Url $PortalAdminUrl
					}catch{
						throw "[WARNING] Unable to Update-PortalSSLCertificate:- $_"
					}
					try{
                        Write-Verbose "Deleting Portal Certificate with alias $CName"
                        Delete-PortalCertificate -PortalHostName $FQDN -SiteName $SiteName -Token $token.token -Referer $Referer -CName $CName
                    }catch{
                        throw "[WARNING] Unable to Delete-PortalCertificate:- $_"
                    }
                }
            }
        }

        if($ImportExistingCertFlag){
			Write-Verbose "Importing exsting certificate with alias $CName"
			try{
				Import-ExistingCertificate -PortalHostName $FQDN -SiteName $SiteName -Token $token.token `
					-Referer $Referer -CertAlias $CName -CertificateFilePath $CertificateFileLocation -CertificatePassword $CertificatePassword
			}catch{
				throw "[WARNING] Error Import-ExistingCertificate:- $_"
			}
        }
        
		if($certsConfig.webServerCertificateAlias -ine $CName -or $ImportExistingCertFlag) {
			Write-Verbose "Updating Alias to use $CName"
			try{
				Update-PortalSSLCertificate -PortalHostName $FQDN -SiteName $SiteName -Token $token.token -Referer $Referer -CertAlias $CName 
				Write-Verbose "Updating an SSL Certificate causes the web server to restart asynchronously. Waiting 180 seconds before checking for intitialization"
                Start-Sleep -Seconds 180
                Wait-ForUrl -Url $PortalAdminUrl
                if($DeleteTempCert){
                    Write-Verbose "Deleting Temp Certificate with alias $($CName)-temp"
                    Delete-PortalCertificate -PortalHostName $FQDN -SiteName $SiteName -Token $token.token -Referer $Referer -CName "$($CName)-temp"
                }
			}catch{
				throw "[WARNING] Unable to Update-PortalSSLCertificate:- $_"
            }
		}else{
			Write-Verbose "SSL Certificate alias $CName is the current one"
		}     
		
        Write-Verbose "Waiting for '$PortalAdminUrl' to initialize"
		Wait-ForUrl -Url $PortalAdminUrl

		try{
			Write-Verbose 'Verifying that SSL Certificates config for site can be retrieved'
			$certsConfig = Get-SSLCertificatesForPortal -PortalHostName $FQDN -SiteName $SiteName -Token $token.token -Referer $Referer -ErrorAction SilentlyContinue
			Write-Verbose "Current Alias for SSL Certificate:- '$($certsConfig.webServerCertificateAlias)'"	
			if(-not($certsConfig.webServerCertificateAlias)) {
				Write-Verbose "Unable to retrive current alias to verify. Restarting Portal Service"
				Restart-PortalService -ServiceName 'Portal for ArcGIS'
				Start-Sleep -Seconds 120
				Write-Verbose "Waiting for '$PortalAdminUrl' to initialize after waiting 150 seconds"
				Wait-ForUrl -Url $PortalAdminUrl
				Write-Verbose "Finished Waiting for '$PortalAdminUrl' to initialize"
			}
		}catch{
			Write-Verbose "[WARNING] Unable to get SSL-CertificatesForPortal:- $_"
		}
    }else{
        Write-Verbose "CertificateFileLocation not specified or '$CertificateFileLocation' not accessible"
        Write-Warning "CertificateFileLocation not specified or '$CertificateFileLocation' not accessible"
	}

	# test and set RootOrIntermediateCertificate
    foreach ($key in ($SslRootOrIntermediate | ConvertFrom-Json)){
        if ($certsConfig.sslCertificates -icontains $key.Alias){
            Write-Verbose "Set RootOrIntermediate $($key.Alias) is in List of SSL-Certificates no Action Required"
        }else{
            Write-Verbose "Set RootOrIntermediate $($key.Alias) is NOT in List of SSL-Certificates Import-RootOrIntermediate"
            try{
                Import-RootOrIntermediateCertificate -PortalHostName $FQDN -SiteName $SiteName -Token $token.token -Referer $Referer -CertAlias $key.Alias -CertificateFilePath $key.Path
            }catch{
                Write-Verbose "Error in Import-RootOrIntermediateCertificate :- $_"
            }
        }
    }
}

function Restart-PortalService
{
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [System.String]
        $ServiceName = 'Portal for ArcGIS'
    )

    try 
    {
		Write-Verbose "Restarting Service $ServiceName"
		Stop-Service -Name $ServiceName -Force -ErrorAction Ignore
		Write-Verbose 'Stopping the service' 
		Wait-ForServiceToReachDesiredState -ServiceName $ServiceName -DesiredState 'Stopped'
		Write-Verbose 'Stopped the service'
	}catch {
        Write-Verbose "[WARNING] Stopping Service $_"
    }

	try {
		Write-Verbose 'Starting the service'
		Start-Service -Name $ServiceName -ErrorAction Ignore        
		Wait-ForServiceToReachDesiredState -ServiceName $ServiceName -DesiredState 'Running'
		Write-Verbose "Restarted Service '$ServiceName'"
	}catch {
        Write-Verbose "[WARNING] Starting Service $_"
    }
}

function Test-TargetResource
{
	[CmdletBinding()]
	[OutputType([System.Boolean])]
	param
	(
		[parameter(Mandatory = $true)]
		[System.String]
		$SiteName,

		[ValidateSet("Present","Absent")]
		[System.String]
		$Ensure,

		[System.Management.Automation.PSCredential]
		$SiteAdministrator,

		[System.String]
		$CertificateFileLocation,

		[System.String]
		$CertificatePassword,

        [System.String]
		$CName,

		[System.String]
		$PortalEndPoint,

		[System.String]
		$ServerEndPoint,

        [System.String]
        $SslRootOrIntermediate
	)   
   
	Import-Module $PSScriptRoot\..\..\ArcGISUtility.psm1 -Verbose:$false

    [System.Reflection.Assembly]::LoadWithPartialName("System.Web") | Out-Null
    $result = $false
    $MachineEndPoint = if($PortalEndPoint) { $PortalEndPoint} else { $env:COMPUTERNAME }	
	$FQDN = $MachineEndPoint
    if(-not($FQDN -as [ipaddress])) {
        $FQDN = Get-FQDN $MachineEndPoint
    }
    $PortalUrl = "https://$($FQDN):7443" 
	#Write-Verbose "Waiting for portal at 'https://$($FQDN):7443/$($SiteName)/sharing/rest/' to initialize" 
	#Wait-ForUrl -Url "https://$($FQDN):7443/$($SiteName)/sharing/rest/" -MaxWaitTimeInSeconds 180 -HttpMethod 'GET' -LogFailures -MaximumRedirection -1
	$Referer = $PortalUrl
    $token = $null
    try{ 
		Wait-ForUrl "https://$($FQDN):7443/$SiteName/sharing/rest/generateToken"
        $token = Get-PortalToken -PortalHostName $FQDN -SiteName $SiteName -Credential $SiteAdministrator -Referer $Referer 
        if(-not($token)) {
            # Unable to retrieve token. Restart the service and try again
            $ServiceName = 'Portal for ArcGIS'
            try {
			    Write-Verbose "Restarting Service $ServiceName"
			    Stop-Service -Name $ServiceName -Force -ErrorAction Ignore
			    Write-Verbose 'Stopping the service' 
			    Wait-ForServiceToReachDesiredState -ServiceName $ServiceName -DesiredState 'Stopped'
			    Write-Verbose 'Stopped the service'
		    }catch {
                Write-Verbose "[WARNING] Stopping Service $_"
            }
		    try {
			    Write-Verbose 'Starting the service'
			    Start-Service -Name $ServiceName -ErrorAction Ignore        
			    Wait-ForServiceToReachDesiredState -ServiceName $ServiceName -DesiredState 'Running'
			    Write-Verbose "Restarted Service $ServiceName"
		    }catch {
                Write-Verbose "[WARNING] Starting Service $_"
            }
        }
        $token = Get-PortalToken -PortalHostName $FQDN -SiteName $SiteName  -Credential $SiteAdministrator -Referer $Referer 
    }
    catch {
        Write-Verbose "[WARNING] Unable to get token:- $_"
    }
	if(-not($token.token)) {
		throw "Unable to retrieve Portal Token for '$($SiteAdministrator.UserName)'"
	}else {
        Write-Verbose "Retrieved Portal Token"
    }
    Write-Verbose "Retrieve SSL Certificate for Portal from $FQDN and checking for Alias $CNAME"
	try{
		$certsConfig = Get-SSLCertificatesForPortal -PortalHostName $FQDN -SiteName $Sitename -Token $token.token -Referer $Referer 
		Write-Verbose "Number of certificates:- $($certsConfig.sslCertificates.Length) Certificates:- '$($certsConfig.sslCertificates -join ',')' Current Alias :- '$($certsConfig.webServerCertificateAlias)'"
        $result = ($certsConfig.sslCertificates -icontains $CName) -and ($certsConfig.webServerCertificateAlias -ieq $CName) 
        
	}catch{
		Write-Verbose "Error in Get-SSLCertificatesForPortal :- $_"
		$result = $false
	}

	if($result){
        Write-Verbose "Certificate $($certsConfig.webServerCertificateAlias) matches expected alias of '$CNAME'"
        $certConfig = Get-SSLCertificatesForPortal -PortalHostName $FQDN -SiteName $SiteName -Token $token.token -Referer $Referer -CName $CName
        if($CertificateFileLocation -and $CertificatePassword) {
            Write-Verbose "Examine certificate from $CertificateFileLocation"
            $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
            $cert.Import($CertificateFileLocation, $CertificatePassword, 'DefaultKeySet')
            $NewCertThumbprint = $cert.Thumbprint
            Write-Verbose "Thumbprint for the supplied certificate is $NewCertThumbprint"
            if($certConfig.sha1Fingerprint -ine $NewCertThumbprint){
                $result = $false
            }
        }
    }
    else {
        Write-Verbose "Certificate $($certsConfig.webServerCertificateAlias) does not match expected alias of '$CNAME'"
    }

	if ($result) { # test for RootOrIntermediate Certificate-List
        $testRootorIntermediate = $true
        foreach ($key in ($SslRootOrIntermediate | ConvertFrom-Json)){
            if ($certsConfig.sslCertificates -icontains $key.Alias){
                Write-Verbose "Test RootOrIntermediate $($key.Alias) is in List of SSL-Certificates"
            }else{
                $testRootorIntermediate = $false
                Write-Verbose "Test RootOrIntermediate $($key.Alias) is NOT in List of SSL-Certificates"
                break;
            }
        }
        $result = $testRootorIntermediate
    }

    if($Ensure -ieq 'Present'){           
           $result
    }elseif($Ensure -ieq 'Absent'){        
        (-not($result))
    }
}

function Get-SSLCertificatesForPortal
{
    param(
        [System.String]
        $PortalHostName = 'localhost',

        [System.String]
        $CName,

        [System.String]
        $SiteName = 'arcgis',

        [System.String]
        $Token,

        [System.String]
        $Referer
    )

	try {
        if($CName){
            Invoke-ArcGISWebRequest -Url "https://$($PortalHostName):7443/$($SiteName)/portaladmin/security/sslCertificates/$($CName)" -HttpFormParameters @{ f = 'json'; token = $Token } -Referer $Referer -HttpMethod 'GET' -TimeOutSec 120
        }else{
            Invoke-ArcGISWebRequest -Url "https://$($PortalHostName):7443/$($SiteName)/portaladmin/security/sslCertificates" -HttpFormParameters @{ f = 'json'; token = $Token } -Referer $Referer -HttpMethod 'GET' -TimeOutSec 120
        }
	}
	catch {
		Write-Verbose "[WARNING]:- Get-SSLCertificatesForPortal encountered an error during execution. Error:- $_"
	}
}

function Delete-PortalCertificate{
    param(
        [System.String]
        $PortalHostName = 'localhost',

        [System.String]
        $CName,

        [System.String]
        $SiteName = 'arcgis',

        [System.String]
        $Token,

        [System.String]
        $Referer
    )
    try {
        Invoke-ArcGISWebRequest -Url "https://$($PortalHostName):7443/$($SiteName)/portaladmin/security/sslCertificates/$($CName)/delete" -HttpFormParameters @{ f = 'json'; token = $Token } -Referer $Referer -HttpMethod 'POST' -TimeOutSec 120
    }catch{
        Write-Verbose "[WARNING]:- Delete-PortalCertificate encountered an error during execution. Error:- $_"
    }
}

function Import-ExistingCertificate
{
    [CmdletBinding()]
    param(
        [System.String]
        $PortalHostName = 'localhost', 

        [System.String]
        $SiteName = 'arcgis', 

        [System.String]
        $Token, 

        [System.String]
        $Referer, 

        [System.String]
        $CertAlias, 

        [System.String]
        $CertificatePassword, 

        [System.String]
        $CertificateFilePath
    )

    $ImportCertUrl  = "https://$($PortalHostName):7443/$SiteName/portaladmin/security/sslCertificates/importExistingServerCertificate"
    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true} # Allow self-signed certificates
    [System.Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls
    $props = @{ f= 'json'; token = $Token; alias = $CertAlias; password = $CertificatePassword  }    
    $res = Upload-File -url $ImportCertUrl -filePath $CertificateFilePath -fileContentType 'application/x-pkcs12' -formParams $props -Referer $Referer -fileParameterName 'file'    
    if($res -and $res.Content) {
        $response = $res | ConvertFrom-Json
        Check-ResponseStatus $response -Url $ImportCACertUrl
    } else {
        Write-Verbose "[WARNING] Response from $ImportCertUrl was null"
    }
}

function Import-RootOrIntermediateCertificate
{
    [CmdletBinding()]
    param(
        [System.String]
        $PortalHostName = 'localhost', 

        [System.String]
        $SiteName = 'arcgis', 

        [System.String]
        $Token, 

        [System.String]
        $Referer, 

        [System.String]
        $CertAlias, 

        [System.String]
        $CertificateFilePath
    )

    $ImportCertUrl  = "https://$($PortalHostName):7443/$SiteName/portaladmin/security/sslCertificates/importRootOrIntermediate"
    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true} # Allow self-signed certificates

    $props = @{ f= 'json'; token = $Token; alias = $CertAlias; norestart = $true  } # norestart requires ArcGIS Server 10.6 or higher
    $res = Upload-File -url $ImportCertUrl -filePath $CertificateFilePath -fileContentType 'application/x-pkcs12' -formParams $props -Referer $Referer -fileParameterName 'file'    
    if($res -and $res.Content) {
        $response = $res | ConvertFrom-Json
        Check-ResponseStatus $response -Url $ImportCACertUrl
    } else {
        Write-Verbose "[WARNING] Response from $ImportCertUrl was null"
    }
}

function Update-PortalSSLCertificate
{
    [CmdletBinding()]
    param(
        [System.String]
        $PortalHostName = 'localhost', 

        [System.String]
        $SiteName = 'arcgis', 

        [System.String]
        $Token, 

        [System.String]
        $Referer, 

        [System.String]
        $CertAlias
    )

    Invoke-ArcGISWebRequest -Url "https://$($PortalHostName):7443/$($SiteName)/portaladmin/security/sslCertificates/update" -HttpFormParameters @{ f = 'json'; token = $Token; webServerCertificateAlias = $CertAlias; sslProtocols = 'TLSv1.2,TLSv1.1,TLSv1' } -Referer $Referer
}

Export-ModuleMember -Function *-TargetResource