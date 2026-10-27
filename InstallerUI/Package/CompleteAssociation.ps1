. (Join-Path $PSScriptRoot 'Common.ps1')
$code=1;$logged=$false
try {
    Assert-Administrator;Enter-InputBridgeOperation
    Import-InputBridgeRecoveryAssembly
    $state=Read-InputBridgeState
    if(!$state -or $state.PendingUninstall -or !$state.ControllerAssociation.Pending){$code=0}
    else {
        Start-InputBridgeLog 'complete-association';$logged=$true
        $payload=Join-Path $PSScriptRoot 'Payload'
        Assert-InputBridgePayload $payload|Out-Null
        $expected=(Get-FileHash -LiteralPath (Join-Path $payload 'WindowsKeyboardMouseBridge.sys') -Algorithm SHA256).Hash
        if($state.ControllerAssociation.DriverSHA256 -cne $expected){throw 'Un autre paquet a demande cette association. Reouvrir son installeur ; aucune association modifiee.'}
        $boot=(Get-CimInstance Win32_OperatingSystem).LastBootUpTime.ToUniversalTime().ToString('o')
        if($state.ControllerAssociation.Boot -eq $boot){
            Write-Host 'Windows doit redemarrer avant la suite des associations. Aucun peripherique redemarre par ce script.';$code=3010
        } else {
            $driver=Get-CimInstance Win32_SystemDriver -Filter "Name='WindowsKeyboardMouseBridge'"
            $driverPath=[string]$driver.PathName
            if($driverPath.StartsWith('\SystemRoot\',[StringComparison]::OrdinalIgnoreCase)){$driverPath=Join-Path $env:WINDIR $driverPath.Substring(12)}
            $driverPath=$driverPath -replace '^\\\?\?\\',''
            if(!$driver -or $driver.State -ne 'Running' -or (Get-FileHash -LiteralPath $driverPath -Algorithm SHA256).Hash -cne $expected){throw 'Le pilote attendu ne fonctionne pas apres redemarrage. Association differee conservee.'}
            $helper=Join-Path $payload 'InputBridgeExample.exe'
            if((Invoke-InputBridgeSetupHelper $helper @('--status') 20000) -ne 0){throw 'API du pilote indisponible apres redemarrage.'}
            # Include devices first connected after the initial installation
            # in the same protected restoration journal before editing filters.
            Set-InputBridgePhase 'Resume pending device association'
            $state=Save-InputBridgeBaseline
            $script:InputBridgeBeforeSetup=Get-InputBridgeSetupState $helper
            # Finish only the deferred input associations. Do not repeat mapper
            # installation or rebind the root control endpoint on every launch.
            $code=Invoke-InputBridgeSetupHelper $helper @('--init-all','--quiet')
            if($code -notin @(0,3010)){$state.ControllerAssociation.LastError=$code;Write-InputBridgeState $state;throw ('Input initialization failed: '+$code)}
            Set-InputBridgePhase 'Verify Windows device startup'
            $code=Wait-InputBridgeSetupDevices $helper $script:InputBridgeBeforeSetup -RestartRequested:($code -eq 3010)
            $state=Read-InputBridgeState
            $state.ControllerAssociation.Pending=($code -ne 0)
            $state.ControllerAssociation.Boot=$boot
            $state.ControllerAssociation.LastError=if($code -in @(0,3010)){0}else{$code}
            Write-InputBridgeState $state
            if($code -notin @(0,3010)){throw ('Association des manettes en echec : '+$code)}
            Write-Host $(if($code -eq 0){'Associations terminees. La capture reste a verifier dans le diagnostic.'}else{'Manettes associees ; Windows demande un dernier redemarrage pour charger leurs filtres.'})
        }
    }
    if($logged){Complete-InputBridgeOperation $code}
}catch{$code=if($logged){Write-InputBridgeFailure $_}else{Write-Host $_.Exception.ToString();if($script:InputBridgeLastExitCode -notin @(0,3010)){$script:InputBridgeLastExitCode}else{1}}}
finally{try{if($logged){Stop-Transcript|Out-Null}}finally{Exit-InputBridgeOperation}}
exit $code
