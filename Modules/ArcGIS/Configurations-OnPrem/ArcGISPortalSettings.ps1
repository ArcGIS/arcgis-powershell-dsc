Configuration ArcGISPortalSettings{
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullorEmpty()]
        [System.Management.Automation.PSCredential]
        $PortalAdministratorCredential,

        [Parameter(Mandatory=$false)]
        [System.String]
        $PrimaryPortalMachine,
        
        [Parameter(Mandatory=$false)]
        [System.String]
        $ExternalDNSHostName,

        [Parameter(Mandatory=$false)]
        [System.String]
        $PortalContext,

        [Parameter(Mandatory=$false)]
        [System.String]
        $InternalLoadBalancer,
        
        [Parameter(Mandatory=$false)]
        [System.Int32]
        $InternalLoadBalancerPort
    )

    Import-DscResource -ModuleName PSDesiredStateConfiguration
    Import-DSCResource -ModuleName @{ModuleName="ArcGIS";ModuleVersion="3.3.0"}
    Import-DscResource -Name ArcGIS_PortalSettings
    
    Node $AllNodes.NodeName
    {
        if($Node.Thumbprint){
            LocalConfigurationManager
            {
                CertificateId = $Node.Thumbprint
            }
        }
        
        if($Node.NodeName -ieq $PrimaryPortalMachine){
            ArcGIS_PortalSettings PortalSettings
            {
                PortalHostName          = Get-FQDN $PrimaryPortalMachine
                ExternalDNSName         = $ExternalDNSHostName
                PortalContext           = $PortalContext
                PortalEndPoint          = if($InternalLoadBalancer){ $InternalLoadBalancer }else{ if($ExternalDNSHostName){ $ExternalDNSHostName }else{ Get-FQDN $PrimaryPortalMachine }}
                PortalEndPointContext   = if($InternalLoadBalancer -or !$ExternalDNSHostName){ 'arcgis' }else{ $PortalContext }
                PortalEndPointPort      = if($InternalLoadBalancerPort) { $InternalLoadBalancerPort }elseif(!$ExternalDNSHostName) { 7443 }else { 443 }
                PortalAdministrator     = $PortalAdministratorCredential
            }
        }
    }
}