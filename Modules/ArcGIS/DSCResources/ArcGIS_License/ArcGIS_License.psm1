<#
    .SYNOPSIS
        Licenses the product (Server or Portal) depending on the params specified.
    .PARAMETER Ensure
        Take the values Present or Absent. 
        - "Present" ensures that Component in Licensed, if not.
        - "Absent" ensures that Component in Unlicensed (Not Implemented).
    .PARAMETER LicenseFilePath
        Path to License File 
    .PARAMETER Password
        Optional Password for the corresponding License File 
    .PARAMETER Version
        Optional Version for the corresponding License File 
    .PARAMETER Component
        Product being Licensed (Server or Portal)
    .PARAMETER ServerRole
        (Optional - Required only for Server) Server Role for which the product is being Licensed
    .PARAMETER IsSingleUse
        Boolean to tell if Pro or Desktop is using Single Use License.
    .PARAMETER Force
        Boolean to Force the product to be licensed again, even if already done.

#>

function Get-TargetResource
{
	[CmdletBinding()]
	[OutputType([System.Collections.Hashtable])]
	param
	(
		[parameter(Mandatory = $true)]
		[System.String]
		$LicenseFilePath
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
        $LicenseFilePath,
        
        [parameter(Mandatory = $false)]
		[System.String]
        $Password,

        [parameter(Mandatory = $false)]
		[System.String]
		$Version,

		[ValidateSet("Present","Absent")]
		[System.String]
		$Ensure,

        [ValidateSet("Server","Portal","Desktop","Pro","NotebookServer")]
		[System.String]
		$Component,

		[ValidateSet("ImageServer","GeoEvent","GeoAnalytics","GeneralPurposeServer","HostingServer","NotebookServer")]
		[System.String]
        $ServerRole = 'GeneralPurposeServer',

        [parameter(Mandatory = $false)]
        [System.Boolean]
        $IsSingleUse,
        
        [parameter(Mandatory = $false)]
        [System.Boolean]
		$Force= $False
	)

    Import-Module $PSScriptRoot\..\..\ArcGISUtility.psm1 -Verbose:$false

	if(-not(Test-Path $LicenseFilePath)){
        throw "License file not found at $LicenseFilePath"
    }

    if($Ensure -ieq 'Present') {
        [string]$RealVersion = @()
        if(-not($Version)){
            try{
                $ErrorActionPreference = "Stop"; #Make all errors terminating
                <#$RegistryPath = 'HKLM:\SOFTWARE\ESRI\ArcGIS'
                if($Component -ieq 'Desktop' -or $Component -ieq 'Pro') {
                    $RegistryPath = 'HKLM:\SOFTWARE\WoW6432Node\esri\ArcGIS'
                } 
                $RealVersion = (Get-ItemProperty -Path $RegistryPath).RealVersion#>
                $ComponentName = if($Component -ieq 'NotebookServer'){ "Notebook Server" }else{ $Component }
                $RealVersion = (get-wmiobject Win32_Product| Where-Object {$_.Name -match $ComponentName -and $_.Vendor -eq 'Environmental Systems Research Institute, Inc.'}).Version
            }catch{
                throw "Couldn't Find The Product - $Component"            
            }finally{
                $ErrorActionPreference = "Continue"; #Reset the error action pref to default
            }
        }else{
            $RealVersion = $Version
        }
        Write-Verbose "RealVersion of ArcGIS Software:- $RealVersion" 
        $RealVersion = $RealVersion.Split('.')[0] + '.' + $RealVersion.Split('.')[1] 
        $LicenseVersion = if($Component -ieq 'Pro'){ '10.6' }else{ $RealVersion }

        Write-Verbose "Licensing from $LicenseFilePath" 
        if($Component -ieq 'Desktop' -or $Component -ieq 'Pro') {
            Write-Verbose "Version $LicenseVersion Component $Component" 
            License-Software -Product $Component -LicenseFilePath $LicenseFilePath -Version $LicenseVersion -Password $Password -IsSingleUse $IsSingleUse
        }
        else {
            Write-Verbose "Version $LicenseVersion Component $Component Role $ServerRole" 
            $StdOutputLogFilePath = Join-Path $env:TEMP "$(Get-Date -format "dd-MM-yy-HH-mm")-stdlog.txt"
            $StdErrLogFilePath = Join-Path $env:TEMP "$(Get-Date -format "dd-MM-yy-HH-mm")-stderr.txt"
            Write-Verbose "StdOutputLogFilePath:- $StdOutputLogFilePath" 
            Write-Verbose "StdErrLogFilePath:- $StdErrLogFilePath" 
            License-Software -Product $Component -LicenseFilePath $LicenseFilePath `
                         -Version $LicenseVersion -Password $Password -IsSingleUse $IsSingleUse `
                         -StdOutputLogFilePath $StdOutputLogFilePath -StdErrLogFilePath $StdErrLogFilePath
        }
    }else {
        throw "Ensure = 'Absent' not implemented"
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
        $LicenseFilePath,
        
        [parameter(Mandatory = $false)]
		[System.String]
		$Password,

        [parameter(Mandatory = $false)]
		[System.String]
		$Version,

		[ValidateSet("Present","Absent")]
		[System.String]
		$Ensure,

		[ValidateSet("Server","Portal","Desktop","Pro","NotebookServer")]
		[System.String]
		$Component,

		[ValidateSet("ImageServer","GeoEvent","GeoAnalytics","GeneralPurposeServer","HostingServer","NotebookServer")]
		[System.String]
        $ServerRole = 'GeneralPurposeServer',

        [parameter(Mandatory = $false)]
        [System.Boolean]
        $IsSingleUse,
        
        [parameter(Mandatory = $false)]
        [System.Boolean]
		$Force = $False
	)

    Import-Module $PSScriptRoot\..\..\ArcGISUtility.psm1 -Verbose:$false

    [string]$RealVersion = @()
    $result = $false
    if(-not($Version)){
        try{
            $ErrorActionPreference = "Stop"; #Make all errors terminating
            <#$RegistryPath = 'HKLM:\SOFTWARE\ESRI\ArcGIS'
            if($Component -ieq 'Desktop' -or $Component -ieq 'Pro') {
                $RegistryPath = 'HKLM:\SOFTWARE\WoW6432Node\esri\ArcGIS'
            } 
            $RealVersion = (Get-ItemProperty -Path $RegistryPath).RealVersion#>
            $ComponentName = if($Component -ieq 'NotebookServer'){ "Notebook Server" }else{ $Component }
            $RealVersion = (get-wmiobject Win32_Product| Where-Object {$_.Name -match $ComponentName -and $_.Vendor -eq 'Environmental Systems Research Institute, Inc.'}).Version
        }catch{
            throw "Couldn't Find The Product - $Component"        
        }finally{
            $ErrorActionPreference = "Continue"; #Reset the error action pref to default
        }
    }else{
        $RealVersion = $Version
    }

    Write-Verbose "RealVersion of ArcGIS Software to be Licensed:- $RealVersion" 
    $RealVersion = $RealVersion.Split('.')[0] + '.' + $RealVersion.Split('.')[1] 
    $LicenseVersion = if($Component -ieq 'Pro'){ '10.6' }else{ $RealVersion }

    Write-Verbose "Version $LicenseVersion" 
    if($Component -ieq 'Desktop') {
        Write-Verbose "TODO:- Check for Desktop license. For now forcing Software Authorization Tool to License Pro."
        <#$RegPath = "HKLM:\SOFTWARE\Wow6432Node\esri\Python$($Version)"
        if(Test-Path $RegPath -ErrorAction Ignore) {            
            $PythonInstallDir = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Wow6432Node\esri\Python$($Version)").PythonDir
            $PythonPath = ((Get-ChildItem -Path $PythonInstallDir -Filter 'python.exe' -Recurse -File) | Select-Object -First 1 -ErrorAction Ignore)        
            $PythonInterpreterPath = $PythonPath.FullName

            $TempPythonFile = [System.IO.Path]::GetTempFileName()
            Set-Content -Path $TempPythonFile -Value 'import arcpy' -Force            
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = $PythonInterpreterPath
            $psi.Arguments = $TempPythonFile
            $psi.UseShellExecute = $false #start the process from it's own executable file    
            $psi.RedirectStandardOutput = $true #enable the process to read from standard output
            $psi.RedirectStandardError = $true #enable the process to read from standard error

            try 
            {
                Write-Verbose "Testing for desktop initialization using arcpy script and Python interpreter path at $PythonInterpreterPath"
                $p = [System.Diagnostics.Process]::Start($psi)
                $p.WaitForExit()
                $op = $p.StandardOutput.ReadToEnd()
                if($op -and $op.Length -gt 0) {
                    Write-Verbose "Output of python execution:- $op"
                }
                $err = $p.StandardError.ReadToEnd()
                if($err -and $err.Length -gt 0) {
                    Write-Verbose "Error  of python execution process:- $err"
                }
                if($p.ExitCode -eq 0) {                    
                    Write-Verbose "Arcpy initialized correctly indicating successful desktop initialization"
                    if($force){
                        $result = $false
                    }else{
                        $result = $true
                    }
                }else {
                    Write-Verbose "Arcpy initialization did not succeed. Process exit code:- $($p.ExitCode) $p"
                }
            }
            catch{
                Write-Verbose "Error testing for arcpy initialization. Error:- $_"
            }
            finally{
                if($TempPythonFile -and (Test-Path $TempPythonFile)) {
                    Remove-Item $TempPythonFile -ErrorAction Ignore
                }
            }
        }#>
    }
    elseif($Component -ieq 'Pro') {
        Write-Verbose "TODO:- Check for Pro license. For now forcing Software Authorization Tool to License Pro."
    }
    else {
        Write-Verbose "License Check Component:- $Component ServerRole:- $ServerRole"
        $file = "$env:SystemDrive\Program Files\ESRI\License$($LicenseVersion)\sysgen\keycodes"
        if(Test-Path $file) {        
            $searchtexts = @()
            $searchtext = if($RealVersion.StartsWith('10.4')) { 'server' } else { 'svr' }
            if($Component -ieq 'Portal') {
                $searchtexts += 'portal1_'
                $searchtexts += 'portal2_'
                $searchtext = 'portal_'
            }
            elseif($ServerRole -ieq 'ImageServer') {
			    $searchtext = 'imgsvr'
		    }
		    elseif($ServerRole -ieq 'GeoEvent') {
			    $searchtext = 'geoesvr'
		    }
		    elseif($ServerRole -ieq 'GeoAnalytics') {
			    $searchtext = 'geoasvr'
            }
            elseif($Component -ieq 'NotebookServer') {
                $searchtexts += 'notebooksstdsvr'
			    $searchtext = 'notebooksadvsvr'
		    }
            $searchtexts += $searchtext
            foreach($text in $searchtexts) {
                Write-Verbose "Looking for text '$text' in $file"
                Get-Content $file | ForEach-Object {             
                    if($_ -and $_.ToString().StartsWith($text)) {
                        Write-Verbose "Text '$text' found"
                        if($force){
                            $result = $false
                        }else{
                            $result = $true
                        }
                    }
                }
            }
        }
    }
    
    if($Ensure -ieq 'Present') {
	       $result   
    }
    elseif($Ensure -ieq 'Absent') {        
        (-not($result))
    }
}


Export-ModuleMember -Function *-TargetResource

