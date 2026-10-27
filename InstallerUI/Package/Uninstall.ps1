param([switch]$Emergency,[switch]$Finalize)
. (Join-Path $PSScriptRoot 'Common.ps1')
$code=1;$logged=$false
try {
    Assert-Administrator;Enter-InputBridgeOperation
    if($Finalize){$pending=Read-InputBridgeState;if(!$pending -or !$pending.PendingUninstall){Write-Host 'No pending InputBridge cleanup; newer installation preserved.';$code=0;exit 0}}
    Get-InputBridgeWindowsTool 'pnputil.exe'|Out-Null
    Get-InputBridgeWindowsTool 'sc.exe'|Out-Null
    Start-InputBridgeLog 'uninstall';$logged=$true
    Set-InputBridgePhase 'Prepare Windows input restoration'
    $code=Invoke-InputBridgeCleanUninstall -Finalize:$Finalize
    Complete-InputBridgeOperation $code
    Write-Host 'Windows input restoration processed. Boot settings and pre-existing certificates preserved.'
    if($code -eq 0){
        Stop-Transcript|Out-Null;$logged=$false
        Remove-InputBridgeOwnedTree (Get-InputBridgeRecoveryRoot) (Join-Path $env:ProgramFiles 'WindowsKeyboardMouseBridge\Recovery')
        $parent=Join-Path $env:ProgramFiles 'WindowsKeyboardMouseBridge'
        if((Test-Path -LiteralPath $parent) -and @(Get-ChildItem -LiteralPath $parent -Force).Count -eq 0){Remove-Item -LiteralPath $parent}
        Remove-InputBridgeOwnedTree (Get-InputBridgeDataRoot) (Join-Path $env:ProgramData 'WindowsKeyboardMouseBridge')
    } else {Write-Host 'Windows requires a restart. Remaining owned files will be removed automatically after that restart.'}
} catch {$code=if($logged){Write-InputBridgeFailure $_}else{Write-Host $_.Exception.ToString();if($script:InputBridgeLastExitCode -notin @(0,3010)){$script:InputBridgeLastExitCode}else{1}}}
finally {try{if($logged){Stop-Transcript|Out-Null}}finally{Exit-InputBridgeOperation}}
if($Emergency -and $code -eq 3010){
    & (Join-Path $env:WINDIR 'System32\shutdown.exe') /r /t 30 /d p:2:4 /c 'InputBridge emergency recovery: restart required to finish restoring Windows input drivers.'
}
exit $code
