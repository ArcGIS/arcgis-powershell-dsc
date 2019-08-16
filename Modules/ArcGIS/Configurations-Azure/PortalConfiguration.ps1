﻿Configuration PortalConfiguration
{
	param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullorEmpty()]
        [System.Management.Automation.PSCredential]
        $ServiceCredential

        ,[Parameter(Mandatory=$false)]
        [System.String]
        $ServiceCredentialIsDomainAccount = 'false'

        ,[Parameter(Mandatory=$true)]
        [ValidateNotNullorEmpty()]
        [System.Management.Automation.PSCredential]
        $SiteAdministratorCredential

        ,[Parameter(Mandatory=$false)]
        [System.String]
        $UseCloudStorage 

        ,[Parameter(Mandatory=$false)]
        [System.String]
        $UseAzureFiles 

        ,[Parameter(Mandatory=$false)]
        [System.Management.Automation.PSCredential]
        $StorageAccountCredential

        ,[Parameter(Mandatory=$true)]
        [System.String]
        $PortalEndpoint

        ,[Parameter(Mandatory=$true)]
        [System.String]
        $ServerEndpoint
        
        ,[Parameter(Mandatory=$false)]
        [System.Management.Automation.PSCredential]
        $SelfSignedSSLCertificatePassword
                
        ,[Parameter(Mandatory=$false)]
        [System.String]
        $PortalLicenseFileUrl

        ,[Parameter(Mandatory=$false)]
        [System.String]
        $PortalLicenseUserType

        ,[Parameter(Mandatory=$true)]
        [System.String]
        $PortalMachineNames

		,[Parameter(Mandatory=$true)]
        [System.String]
        $ServerMachineNames

        ,[Parameter(Mandatory=$true)]
        [System.String]
        $FileShareMachineName

        ,[Parameter(Mandatory=$true)]
        [System.String]
        $ExternalDNSHostName    
        
        ,[Parameter(Mandatory=$false)]
        [System.Int32]
        $OSDiskSize = 0

        ,[Parameter(Mandatory=$false)]
        [System.String]
        $EnableDataDisk      
        
         ,[Parameter(Mandatory=$false)]
        [System.String]
        $FileShareName = 'fileshare'         
        
        ,[Parameter(Mandatory=$false)]
        [System.String]
        $DebugMode
    )

    function Extract-FileNameFromUrl
    {
        param(
            [string]$Url
        )
        $FileName = $Url
        if($FileName) {
            $pos = $FileName.IndexOf('?')
            if($pos -gt 0) { 
                $FileName = $FileName.Substring(0, $pos) 
            } 
            $FileName = $FileName.Substring($FileName.LastIndexOf('/')+1)   
        }     
        $FileName
    }

	Import-DscResource -Name ArcGIS_License
	Import-DscResource -Name ArcGIS_Portal
    Import-DscResource -Name ArcGIS_Portal_TLS
    Import-DscResource -Name ArcGIS_Service_Account
    Import-DscResource -name ArcGIS_WindowsService
    Import-DscResource -Name ArcGIS_xFirewall
    Import-DscResource -Name ArcGIS_xDisk
    Import-DscResource -Name ArcGIS_Disk
    
    ##
    ## Download license file
    ##
    if($PortalLicenseFileUrl -and ($PortalLicenseFileUrl.Trim().Length -gt 0)) {
        $PortalLicenseFileName = Extract-FileNameFromUrl $PortalLicenseFileUrl
        Invoke-WebRequest -OutFile $PortalLicenseFileName -Uri $PortalLicenseFileUrl -UseBasicParsing -ErrorAction Ignore
    }    

	$ServerHostNames = ($ServerMachineNames -split ',')
    $ServerMachineName = $ServerHostNames | Select-Object -First 1
    $PortalHostNames = ($PortalMachineNames -split ',')
    $PortalHostName = $PortalHostNames | Select-Object -First 1    
    $ipaddress = (Resolve-DnsName -Name $FileShareMachineName -Type A -ErrorAction Ignore | Select-Object -First 1).IPAddress    
    if(-not($ipaddress)) { $ipaddress = $FileShareMachineName }
    $FolderName = $ExternalDNSHostName.Substring(0, $ExternalDNSHostName.IndexOf('.')).ToLower()
    $FileShareRootPath = "\\$FileShareMachineName\$FileShareName"
    $ContentStoreLocation = "\\$FileShareMachineName\$FileShareName\$FolderName\portal\content"   
    $CertificateFileName  = 'SSLCertificateForPortal.pfx'
    $CertificateFileLocation = "\\$FileShareMachineName\$FileShareName\Certs\$CertificateFileName"
    $CertificateLocalFilePath =  (Join-Path $env:TEMP $CertificateFileName)
    $Join = ($env:ComputerName -ine $PortalHostName)    
    $PeerMachineName = $null
    if($PortalHostNames.Length -gt 1) {
      $PeerMachineName = $PortalHostNames | Select-Object -Last 1
    }
    $IsDebugMode = $DebugMode -ieq 'true'
    $IsServiceCredentialDomainAccount = $ServiceCredentialIsDomainAccount -ieq 'true'
    $IsHAPortal = ($PortalHostName -ine $PeerMachineName) -and ($PeerMachineName)

    if(($UseCloudStorage -ieq 'True') -and $StorageAccountCredential) 
    {
        $Namespace = $ExternalDNSHostName
        $Pos = $Namespace.IndexOf('.')
        if($Pos -gt 0) { $Namespace = $Namespace.Substring(0, $Pos) }        
        $Namespace = [System.Text.RegularExpressions.Regex]::Replace($Namespace, '[\W]', '') # Sanitize
        $AccountName = $StorageAccountCredential.UserName
		$EndpointSuffix = ''
        $Pos = $StorageAccountCredential.UserName.IndexOf('.blob.')
        if($Pos -gt -1) {
            $AccountName = $StorageAccountCredential.UserName.Substring(0, $Pos)
			$EndpointSuffix = $StorageAccountCredential.UserName.Substring($Pos + 6) # Remove the hostname and .blob. suffix to get the storage endpoint suffix
			$EndpointSuffix = ";EndpointSuffix=$($EndpointSuffix)"
        }

        if($UseAzureFiles -ieq 'True') {
            $AzureFilesEndpoint = $StorageAccountCredential.UserName.Replace('.blob.','.file.')                        
            $FileShareName = $FileShareName.ToLower() # Azure file shares need to be lower case
            $FolderName = $ExternalDNSHostName.Substring(0, $ExternalDNSHostName.IndexOf('.'))
            $ContentStoreLocation = "\\$($AzureFilesEndpoint)\$FileShareName\$FolderName\portal\content"    
        }
        else {
            $AccountKey = $StorageAccountCredential.GetNetworkCredential().Password
            $ContentDirectoryCloudConnectionString = "DefaultEndpointsProtocol=https;AccountName=$($AccountName);AccountKey=$($AccountKey)$($EndpointSuffix)"
		    $ContentDirectoryCloudContainerName = "arcgis-portal-content-$($Namespace)"
        }
    }

	Node localhost
	{
        LocalConfigurationManager
        {
			ActionAfterReboot = 'ContinueConfiguration'            
            ConfigurationMode = 'ApplyOnly'    
            RebootNodeIfNeeded = $true
        }
        
        if($OSDiskSize -gt 0) 
        {
            ArcGIS_Disk OSDiskSize
            {
                DriveLetter = ($env:SystemDrive -replace ":" )
                SizeInGB    = $OSDiskSize
            }
        }
        
        if($EnableDataDisk -ieq 'true')
        {
            ArcGIS_xDisk DataDisk
            {
                DiskNumber  =  2
                DriveLetter = 'F'
            }
        }

        $HasValidServiceCredential = ($ServiceCredential -and ($ServiceCredential.GetNetworkCredential().Password -ine 'Placeholder'))
        if($HasValidServiceCredential) 
        {
            if(-Not($IsServiceCredentialDomainAccount)){
                User ArcGIS_RunAsAccount
                {
                    UserName       = $ServiceCredential.UserName
                    Password       = $ServiceCredential
                    FullName       = 'ArcGIS Service Account'
                    Ensure         = 'Present'
                    PasswordChangeRequired = $false
                    PasswordNeverExpires = $true
                }
            }

            $PortalDependsOn = @('[ArcGIS_Service_Account]Portal_Service_Account')   
            if($PortalLicenseFileName -and ($PortalLicenseFileName.Trim().Length -gt 0) ) 
            {
                if([string]::IsNullOrEmpty($PortalLicenseUserType)){
                    ArcGIS_License PortalLicense
                    {
                        LicenseFilePath = (Join-Path $(Get-Location).Path $PortalLicenseFileName)
                        Ensure          = 'Present'
                        Component       = 'Portal'
                    } 
                    $PortalDependsOn += '[ArcGIS_License]PortalLicense'
                }

                ArcGIS_WindowsService Portal_for_ArcGIS_Service
                {
                    Name            = 'Portal for ArcGIS'
                    Credential      = $ServiceCredential
                    StartupType     = 'Automatic'
                    State           = 'Running' 
                    DependsOn       = if(-Not($IsServiceCredentialDomainAccount)){@('[User]ArcGIS_RunAsAccount')}else{@()}
                }
                
                ArcGIS_Service_Account Portal_Service_Account
		        {
			        Name            = 'Portal for ArcGIS'
                    RunAsAccount    = $ServiceCredential
                    IsDomainAccount = $IsServiceCredentialDomainAccount
			        Ensure          = 'Present'
			        DependsOn       = if(-Not($IsServiceCredentialDomainAccount)){@('[User]ArcGIS_RunAsAccount','[ArcGIS_WindowsService]Portal_for_ArcGIS_Service')}else{@('[ArcGIS_WindowsService]Portal_for_ArcGIS_Service')}
                    DataDir         = @('HKLM:\SOFTWARE\ESRI\Portal for ArcGIS')  
		        }
        
            
                if($AzureFilesEndpoint -and $StorageAccountCredential -and ($UseAzureFiles -ieq 'True')) 
                {
                      $filesStorageAccountName = $AzureFilesEndpoint.Substring(0, $AzureFilesEndpoint.IndexOf('.'))
                      $storageAccountKey       = $StorageAccountCredential.GetNetworkCredential().Password
              
                      Script PersistStorageCredentials
                      {
                          TestScript = { 
                                            $result = cmdkey "/list:$using:AzureFilesEndpoint"
                                            $result | %{Write-verbose -Message "cmdkey: $_" -Verbose}
                                            if($result -like '*none*')
                                            {
                                                return $false
                                            }
                                            return $true
                                        }
                          SetScript = { $result = cmdkey "/add:$using:AzureFilesEndpoint" "/user:$using:filesStorageAccountName" "/pass:$using:storageAccountKey" 
						                $result | %{Write-verbose -Message "cmdkey: $_" -Verbose}
					                  }
                          GetScript            = { return @{} }                  
                          DependsOn            = @('[ArcGIS_Service_Account]Portal_Service_Account')
                          PsDscRunAsCredential = $ServiceCredential # This is critical, cmdkey must run as the service account to persist property
                      }              
                      $PortalDependsOn += '[Script]PersistStorageCredentials'

                      $RootPathOfFileShare = "\\$($AzureFilesEndpoint)\$FileShareName"
                      Script CreatePortalContentFolder
                      {
                          TestScript = { 
                                            Test-Path $using:ContentStoreLocation
                                        }
                          SetScript = {                   
                                          Write-Verbose "Mount to $using:RootPathOfFileShare"
                                          $DriveInfo = New-PSDrive -Name 'Z' -PSProvider FileSystem -Root $using:RootPathOfFileShare
                                          if(-not(Test-Path $using:ContentStoreLocation)) {
                                            Write-Verbose "Creating folder $using:ContentStoreLocation"
                                            New-Item $using:ContentStoreLocation -ItemType directory
                                          }else {
                                            Write-Verbose "Folder '$using:ContentStoreLocation' already exists"
                                          }
					                  }
                          GetScript            = { return @{} }     
                          PsDscRunAsCredential = $ServiceCredential # This is important, only arcgis account has access to the file share on AFS
                      }             
                      $PortalDependsOn += '[Script]CreatePortalContentFolder'
                } 

                Script CopyCertificateFileToLocalMachine
                {
                    GetScript = {
                        $null
                    }
                    SetScript = {    
                        Write-Verbose "Copying from $using:CertificateFileLocation to $using:CertificateLocalFilePath"      
                        $PsDrive = New-PsDrive -Name W -Root $using:FileShareRootPath -PSProvider FileSystem                              
                        Copy-Item -Path $using:CertificateFileLocation -Destination $using:CertificateLocalFilePath -Force  
                        if($PsDrive) {
                            Write-Verbose "Removing Temporary Mapped Drive $($PsDrive.Name)"
                            Remove-PsDrive -Name $PsDrive.Name -Force       
                        }       
                    }
                    TestScript = {   
                        $false
                    }
                    DependsOn             = if(-Not($IsServiceCredentialDomainAccount)){@('[User]ArcGIS_RunAsAccount')}else{@()}
                    PsDscRunAsCredential  = $ServiceCredential # Copy as arcgis account which has access to this share
                } 

		        $PortalDependsOn += '[ArcGIS_xFirewall]Portal_FirewallRules'
                ArcGIS_xFirewall Portal_FirewallRules
		        {
				        Name                  = "PortalforArcGIS" 
				        DisplayName           = "Portal for ArcGIS" 
				        DisplayGroup          = "Portal for ArcGIS" 
				        Ensure                = 'Present'
				        Access                = "Allow" 
				        State                 = "Enabled" 
				        Profile               = ("Domain","Private","Public")
				        LocalPort             = ("7080","7443","7654")                         
				        Protocol              = "TCP" 
		        }

                if($IsHAPortal) 
                {
                    ArcGIS_xFirewall Portal_Database_OutBound
		            {
				            Name                  = "PortalforArcGIS-Outbound" 
				            DisplayName           = "Portal for ArcGIS Outbound" 
				            DisplayGroup          = "Portal for ArcGIS Outbound" 
				            Ensure                = 'Present'
				            Access                = "Allow" 
				            State                 = "Enabled" 
				            Profile               = ("Domain","Private","Public")
				            RemotePort            = ("7654","7120","7220", "7005", "7099", "7199", "5701", "5702")  # Elastic Search uses 7120,7220 and Postgres uses 7654 for replication
				            Direction             = "Outbound"                       
				            Protocol              = "TCP" 
		            } 

                    ArcGIS_xFirewall Portal_Database_InBound
			        {
					        Name                  = "PortalforArcGIS-Inbound" 
					        DisplayName           = "Portal for ArcGIS Inbound" 
					        DisplayGroup          = "Portal for ArcGIS Inbound" 
					        Ensure                = 'Present'
					        Access                = "Allow" 
					        State                 = "Enabled" 
					        Profile               = ("Domain","Private","Public")
					        LocalPort             = ("7120","7220", "5701", "5702")  # Elastic Search uses 7120,7220, Hazelcast uses 5701 and 5702
					        Protocol              = "TCP" 
			        }  
			
			        $PortalDependsOn += @('[ArcGIS_xFirewall]Portal_Database_OutBound','[ArcGIS_xFirewall]Portal_Database_InBound')
                }     

		        ArcGIS_Portal Portal
		        {
                    PortalEndPoint                        = $PortalEndpoint
                    PortalContext                         = 'portal'
                    Ensure                                = 'Present'
                    LicenseFilePath                       = if($PortalLicenseFileName){(Join-Path $(Get-Location).Path $PortalLicenseFileName)}else{$null}
                    UserLicenseType                       = if($PortalLicenseUserType){$PortalLicenseUserType}else{$null}
                    ExternalDNSName                       = $ExternalDNSHostName
                    PortalAdministrator                   = $SiteAdministratorCredential 
			        DependsOn                             = $PortalDependsOn
			        AdminEmail                            = 'portaladmin@admin.com'
			        AdminSecurityQuestionIndex            = 1
			        AdminSecurityAnswer                   = 'timbukto'
                    Join                                  = $Join
                    IsHAPortal                            = $IsHAPortal
			        PeerMachineHostName                   = if($Join) { $PortalHostName } else { $PeerMachineName }
                    ContentDirectoryLocation              = $ContentStoreLocation
                    EnableDebugLogging                    = $IsDebugMode
                    LogLevel                              = if($IsDebugMode) { 'DEBUG' } else { 'WARNING' }
                    ContentDirectoryCloudConnectionString = $ContentDirectoryCloudConnectionString							
		            ContentDirectoryCloudContainerName    = $ContentDirectoryCloudContainerName
		        } 
		
		        ArcGIS_Portal_TLS ArcGIS_Portal_TLS
                {
                    Ensure                  = 'Present'
                    SiteName                = 'arcgis'
                    SiteAdministrator       = $SiteAdministratorCredential 
                    CName                   = $PortalEndPoint
			        #PortalEndPoint         = $PortalEndPoint
			        ServerEndPoint          = $ServerEndPoint
                    CertificateFileLocation = $CertificateLocalFilePath 
                    CertificatePassword     = if($SelfSignedSSLCertificatePassword -and ($SelfSignedSSLCertificatePassword.GetNetworkCredential().Password -ine 'Placeholder')) { $SelfSignedSSLCertificatePassword.GetNetworkCredential().Password } else { $null }
                    DependsOn               = @('[ArcGIS_Portal]Portal')
                }
            }

		    foreach($ServiceToStop in @('ArcGIS Server', 'ArcGIS Data Store', 'ArcGISGeoEvent'))
		    {
			    if(Get-Service $ServiceToStop -ErrorAction Ignore) 
			    {
				    ArcGIS_WindowsService "$($ServiceToStop.Replace(' ','_'))_Service"
				    {
					    Name			= $ServiceToStop
					    Credential		= $ServiceCredential
					    StartupType		= 'Manual'
					    State			= 'Stopped'
					    DependsOn		= if(-Not($IsServiceCredentialDomainAccount)){@('[User]ArcGIS_RunAsAccount')}else{@()}
				    }
			    }
		    }
        }
	}
}