. (Join-Path $PSScriptRoot 'Common.ps1')
$code=1;$logged=$false
try {
    Assert-Administrator
    $payload=Join-Path $PSScriptRoot 'Payload'
    $mode=Assert-InputBridgePayload $payload
    Enter-InputBridgeOperation;Start-InputBridgeLog 'association';$logged=$true
    $payload=Join-Path $PSScriptRoot 'Payload'
    $helper=Join-Path $payload 'InputBridgeExample.exe'
    $mode=Assert-InputBridgePayload $payload
    Set-InputBridgePhase 'Snapshot devices before association'
    Save-InputBridgeBaseline|Out-Null
    $script:InputBridgeBeforeSetup=Get-InputBridgeSetupState $helper
    Set-InputBridgePhase 'Associate supported device instances'
    # Bind using INF files already present in the Driver Store; do not stage or
    # upgrade the bundled driver and do not import certificates in this command.
    $packages=@(Get-InputBridgePackages)
    $paths=@()
    foreach($name in @('WindowsKeyboardMouseBridgekeyboard.inf','WindowsKeyboardMouseBridgemouse.inf','WindowsKeyboardMouseBridgecontrol.inf')) {
        $package=$packages | Where-Object { [IO.Path]::GetFileName($_.OriginalFileName) -eq $name } |
            Sort-Object { [version]$_.Version } -Descending | Select-Object -First 1
        if(!$package -or !(Test-Path -LiteralPath $package.OriginalFileName)) { throw 'Pilote absent du magasin Windows. Executer Installer.bat une premiere fois.' }
        $paths+= $package.OriginalFileName
    }
    $code=Invoke-InputBridgeSetupHelper $helper @('--associate',$paths[0],$paths[1],$paths[2])
    if($code -notin @(0,3010)) { throw "Association interrompue ($code). Certaines associations peuvent avoir reussi ; consulter ce journal puis relancer le script." }
    if($code -eq 0) {
        $code=Invoke-InputBridgeSetupHelper $helper @('--init-all','--quiet')
        if($code -notin @(0,3010)) { throw "Initialisation des manettes en echec: $code" }
    }
    Set-InputBridgePhase 'Verify Windows device startup'
    $code=Wait-InputBridgeSetupDevices $helper $script:InputBridgeBeforeSetup -RestartRequested:($code -eq 3010)
    Set-InputBridgePendingControllers $code (Get-FileHash -LiteralPath (Join-Path $payload 'WindowsKeyboardMouseBridge.sys') -Algorithm SHA256).Hash
    Complete-InputBridgeOperation $code
    Write-Host 'Association terminee. Les pilotes tiers sont laisses en place.'
    if($code -eq 3010) { Write-Host 'Windows demande un redemarrage pour terminer.' }
} catch {$code=if($logged){Write-InputBridgeFailure $_}else{Write-Host $_.Exception.ToString();if($script:InputBridgeLastExitCode -notin @(0,3010)){$script:InputBridgeLastExitCode}else{1}}}
finally {try{if($logged){Stop-Transcript|Out-Null}}finally{Exit-InputBridgeOperation}}
exit $code
