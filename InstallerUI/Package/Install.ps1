. (Join-Path $PSScriptRoot 'Common.ps1')
$code=1;$logged=$false;$bindingStarted=$false;$stagingStarted=$false;$existingPackages=@()
try {
    Assert-Administrator
    $payload=Join-Path $PSScriptRoot 'Payload'
    Assert-InputBridgePayload $payload|Out-Null

    Get-InputBridgeWindowsTool 'pnputil.exe'|Out-Null
    Get-InputBridgeWindowsTool 'sc.exe'|Out-Null
    Enter-InputBridgeOperation
    Assert-InputBridgeInstallationBoundary
    Start-InputBridgeLog 'install';$logged=$true
    Set-InputBridgePhase 'Snapshot original Windows device bindings'
    $baseline=Save-InputBridgeBaseline
    $baseline.PendingUninstall=$false;$baseline.FinalizeAttempts=0;Write-InputBridgeState $baseline
    $helper=Join-Path $payload 'InputBridgeExample.exe'
    $script:InputBridgeBeforeSetup=Get-InputBridgeSetupState $helper
    $existingPackages=@(Get-InputBridgePackages|ForEach-Object Driver)
    Set-InputBridgePhase 'Prepare protected recovery'
    Remove-InputBridgeFinalCleanup
    Install-InputBridgeRecovery
    Set-InputBridgePhase 'Stage Microsoft-signed driver packages'
    $stagingStarted=$true
    foreach($name in @('WindowsKeyboardMouseBridgeKeyboard.inf','WindowsKeyboardMouseBridgeMouse.inf','WindowsKeyboardMouseBridgeControl.inf')){Add-InputBridgePackage (Join-Path $payload $name)}
    Set-InputBridgePhase 'Associate supported device instances'
    $bindingStarted=$true
    $code=Invoke-InputBridgeSetupHelper $helper @('--install',$payload)
    if($code -notin @(0,3010)){throw ('Device association failed: '+$code)}
    if($code -eq 0){
        if((Invoke-InputBridgeSetupHelper $helper @('--status') 20000) -ne 0){throw 'Driver API did not respond after installation.'}
        Set-InputBridgePhase 'Initialize supported input interfaces'
        $code=Invoke-InputBridgeSetupHelper $helper @('--init-all','--quiet')
        if($code -notin @(0,3010)){throw ('Input interface initialization failed: '+$code)}
    }
    if($script:InputBridgeNeedsReboot){$code=3010}
    Set-InputBridgePhase 'Verify Windows device startup'
    $code=Wait-InputBridgeSetupDevices $helper $script:InputBridgeBeforeSetup -RestartRequested:($code -eq 3010)
    Set-InputBridgePendingControllers $code (Get-FileHash -LiteralPath (Join-Path $payload 'WindowsKeyboardMouseBridge.sys') -Algorithm SHA256).Hash
    Get-InputBridgePackages|Select-Object Driver,OriginalFileName|ConvertTo-Json|Set-Content -LiteralPath (Join-Path (Get-InputBridgeDataRoot) 'packages.json') -Encoding UTF8
    Complete-InputBridgeOperation $code
    Write-Host 'Installation verified. Physical input passes through until an application opens capture.'
}catch{
    $code=if($logged){Write-InputBridgeFailure $_}else{Write-Host $_.Exception.ToString();if($script:InputBridgeLastExitCode -notin @(0,3010)){$script:InputBridgeLastExitCode}else{1}}
    $safeToRemove=$false
    if($script:InputBridgeProcessTimedOut){
        Write-Host 'A setup command exceeded its deadline. Binding rollback and package deletion are deferred; recovery and operation evidence are retained. Restart Windows normally, then retry.'
    }elseif($bindingStarted){
        try{
            Write-Host 'Restoring Windows input bindings after the failed installation...'
            $restore=Invoke-InputBridgeSetupHelper $helper @('--restore')
            if($restore -eq 0){
                $remaining=Get-InputBridgeSetupState $helper
                $safeToRemove=@($remaining.devices).Count -eq 0
            }
            if(!$safeToRemove){Write-Host ('Restoration is incomplete or needs a restart (code '+$restore+'). Driver packages and recovery files are retained.')}
        }catch{Write-Host ('Restoration failed; driver packages and recovery are retained: '+$_.Exception.Message)}
    }else{$safeToRemove=$true}
    if($stagingStarted -and $safeToRemove){
        try{foreach($package in (Get-InputBridgePackages|Where-Object {$_.Driver -notin $existingPackages})){Remove-InputBridgePackage $package.Driver}}
        catch{Write-Host ('Owned package cleanup is pending: '+$_.Exception.Message)}
    }
}finally{
    try{if($logged){Stop-Transcript|Out-Null}}finally{Exit-InputBridgeOperation}
}
exit $code
