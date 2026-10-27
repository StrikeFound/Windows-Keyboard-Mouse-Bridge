# Loaded by Common.ps1. No machine mutation occurs just by loading this file.
function Get-InputBridgeDataRoot {Join-Path $env:ProgramData 'WindowsKeyboardMouseBridge'}
function Get-InputBridgeRecoveryRoot {Join-Path $env:ProgramFiles 'WindowsKeyboardMouseBridge\Recovery'}
function Assert-InputBridgeDirectory([string]$Path,[string]$Expected) {
    $full=[IO.Path]::GetFullPath($Path).TrimEnd('\')
    if($full -ine [IO.Path]::GetFullPath($Expected).TrimEnd('\')){throw 'Unexpected InputBridge directory.'}
    $ancestor=$full
    while($ancestor){if(Test-Path -LiteralPath $ancestor){if((Get-Item -LiteralPath $ancestor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'InputBridge directory or ancestor is a reparse point.'}};$ancestor=Split-Path -Parent $ancestor}
    return $full
}
function Initialize-InputBridgeStorage {
    $path=Assert-InputBridgeDirectory (Get-InputBridgeDataRoot) (Join-Path $env:ProgramData 'WindowsKeyboardMouseBridge')
    if(Test-Path -LiteralPath $path){$owner=(Get-Acl -LiteralPath $path).GetOwner([Security.Principal.SecurityIdentifier]).Value;if($owner -notin @('S-1-5-18','S-1-5-32-544')){throw 'Existing InputBridge data folder has an untrusted owner.'}}
    $security=New-Object Security.AccessControl.DirectorySecurity
    $security.SetAccessRuleProtection($true,$false)
    foreach($id in @('S-1-5-18','S-1-5-32-544')){
        $sid=New-Object Security.Principal.SecurityIdentifier($id)
        $security.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($sid,'FullControl','ContainerInherit,ObjectInherit','None','Allow')))
    }
    if(!(Test-Path -LiteralPath $path)){[IO.Directory]::CreateDirectory($path,$security)|Out-Null}else{Set-Acl -LiteralPath $path -AclObject $security}
}
function Enter-InputBridgeOperation {
    $script:InputBridgeOperationOwned=$false
    $security=New-Object Security.AccessControl.MutexSecurity
    foreach($id in @('S-1-5-18','S-1-5-32-544')){$security.AddAccessRule((New-Object Security.AccessControl.MutexAccessRule((New-Object Security.Principal.SecurityIdentifier($id)),'FullControl','Allow')))}
    $familyCreated=$false
    $script:InputBridgeFamilyOwned=$false
    $script:InputBridgeFamilyOperation=New-Object Threading.Mutex($false,'Global\WindowsInputProjects-Maintenance',[ref]$familyCreated,$security)
    try{$family=$script:InputBridgeFamilyOperation.WaitOne(0)}catch [Threading.AbandonedMutexException]{$family=$true}
    if(!$family){$script:InputBridgeFamilyOperation.Dispose();$script:InputBridgeFamilyOperation=$null;$script:InputBridgeLastExitCode=1618;throw 'Another InputBridge edition is performing setup or recovery (Win32 1618). Wait for it to finish.'}
    $script:InputBridgeFamilyOwned=$true
    # Serialize with the original editions too; their immutable packages use
    # this maintenance mutex. Holding it does not authorize changing their data.
    $legacyCreated=$false;$script:InputBridgeLegacyFamilyOwned=$false
    $script:InputBridgeLegacyFamilyOperation=New-Object Threading.Mutex($false,'Global\InterceptorSetup-Maintenance',[ref]$legacyCreated,$security)
    try{$legacy=$script:InputBridgeLegacyFamilyOperation.WaitOne(0)}catch [Threading.AbandonedMutexException]{$legacy=$true}
    if(!$legacy){$script:InputBridgeLegacyFamilyOperation.Dispose();$script:InputBridgeLegacyFamilyOperation=$null;$script:InputBridgeLastExitCode=1618;throw 'An original input edition is performing setup or recovery (Win32 1618). Wait for it to finish.'}
    $script:InputBridgeLegacyFamilyOwned=$true
    $created=$false
    $script:InputBridgeOperation=New-Object Threading.Mutex($false,'Global\WindowsKeyboardMouseBridgeSetup-Installation',[ref]$created,$security)
    try{$acquired=$script:InputBridgeOperation.WaitOne(0)}catch [Threading.AbandonedMutexException]{$acquired=$true}
    if(!$acquired){$script:InputBridgeOperation.Dispose();$script:InputBridgeOperation=$null;$script:InputBridgeLastExitCode=1618;throw 'Another setup or recovery operation for this product is active (Win32 1618). Wait for that operation to finish before retrying.'}
    $script:InputBridgeOperationOwned=$true
}
function Exit-InputBridgeOperation {
    try{
        if($script:InputBridgeOperation){try{if($script:InputBridgeOperationOwned){$script:InputBridgeOperation.ReleaseMutex()}}finally{$script:InputBridgeOperation.Dispose();$script:InputBridgeOperation=$null;$script:InputBridgeOperationOwned=$false}}
    }finally{
        if($script:InputBridgeLegacyFamilyOperation){try{if($script:InputBridgeLegacyFamilyOwned){$script:InputBridgeLegacyFamilyOperation.ReleaseMutex()}}finally{$script:InputBridgeLegacyFamilyOperation.Dispose();$script:InputBridgeLegacyFamilyOperation=$null;$script:InputBridgeLegacyFamilyOwned=$false}}
        if($script:InputBridgeFamilyOperation){try{if($script:InputBridgeFamilyOwned){$script:InputBridgeFamilyOperation.ReleaseMutex()}}finally{$script:InputBridgeFamilyOperation.Dispose();$script:InputBridgeFamilyOperation=$null;$script:InputBridgeFamilyOwned=$false}}
    }
}
function Import-InputBridgeRecoveryAssembly {
    if(!('InputBridgeRecovery.Devices' -as [type])){[Reflection.Assembly]::Load([IO.File]::ReadAllBytes((Join-Path $PSScriptRoot 'Recovery\InputBridgeRecovery.exe')))|Out-Null}
}
function Write-InputBridgeState($State) {
    $path=Join-Path (Get-InputBridgeDataRoot) 'state.json'
    [InputBridgeRecovery.Devices]::WriteState($path,($State|ConvertTo-Json -Depth 12))
}
function Read-InputBridgeState {
    $path=Join-Path (Get-InputBridgeDataRoot) 'state.json'
    if(!(Test-Path -LiteralPath $path)){return $null}
    if((Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Restoration journal is a reparse point.'}
    $owner=(Get-Acl -LiteralPath $path).GetOwner([Security.Principal.SecurityIdentifier]).Value
    if($owner -notin @('S-1-5-18','S-1-5-32-544')){throw 'Restoration journal has an untrusted owner.'}
    $state=Get-Content -LiteralPath $path -Raw -Encoding UTF8|ConvertFrom-Json
    if($state.Schema -ne 1){throw 'Unsupported InputBridge restoration journal.'}
    return $state
}
function Save-InputBridgeBaseline {
    Import-InputBridgeRecoveryAssembly
    $state=Read-InputBridgeState
    if(!$state){$state=[pscustomobject]@{Schema=1;CreatedUtc=[DateTime]::UtcNow.ToString('o');Devices=@();CertificatesAdded=@();PendingUninstall=$false;FinalizeAttempts=0}}
    $known=@{};foreach($device in $state.Devices){$known[$device.Instance]=$true}
    foreach($device in [InputBridgeRecovery.Devices]::Snapshot()){
        if(!$known.ContainsKey($device.Instance)){$state.Devices+= $device;$known[$device.Instance]=$true}
    }
    Write-InputBridgeState $state
    return $state
}
function Register-InputBridgeCertificateAdds($State,[string]$Thumbprint) {
    foreach($store in @('Root','TrustedPublisher')){
        if(!(Test-Path -LiteralPath ('Cert:\LocalMachine\'+$store+'\'+$Thumbprint))){
            if(!@($State.CertificatesAdded|Where-Object {$_.Store -eq $store -and $_.Thumbprint -eq $Thumbprint}).Count){$State.CertificatesAdded+= [pscustomobject]@{Store=$store;Thumbprint=$Thumbprint}}
        }
    }
    Write-InputBridgeState $State
}
function Set-InputBridgePendingControllers([int]$Code,[string]$DriverSHA256) {
    $state=Read-InputBridgeState
    if(!$state){throw 'Installation journal missing for controller association.'}
    $pending=[pscustomobject]@{Pending=($Code -eq 3010);DriverSHA256=$DriverSHA256;Boot=(Get-CimInstance Win32_OperatingSystem).LastBootUpTime.ToUniversalTime().ToString('o');LastError=0}
    $state|Add-Member -NotePropertyName ControllerAssociation -NotePropertyValue $pending -Force
    Write-InputBridgeState $state
    if($pending.Pending){Write-Host 'Association des manettes en attente : apres redemarrage, rouvrir cet installeur pour la terminer.'}
}
function Install-InputBridgeRecovery {
    $root=Assert-InputBridgeDirectory (Get-InputBridgeRecoveryRoot) (Join-Path $env:ProgramFiles 'WindowsKeyboardMouseBridge\Recovery')
    $existing=Get-Service -Name WindowsKeyboardMouseBridgeRecovery -ErrorAction SilentlyContinue
    if($existing){
        $image=[string](Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Services\WindowsKeyboardMouseBridgeRecovery' -Name ImagePath).ImagePath
        if($image.Trim('"') -ine (Join-Path $root 'Recovery\InputBridgeRecovery.exe')){throw 'A different recovery service already uses this name.'}
        if($existing.Status -ne 'Stopped'){$existing.Stop();$existing.WaitForStatus('Stopped',[TimeSpan]::FromSeconds(35))};$existing.Dispose()
    }
    $security=Get-Acl -LiteralPath (Get-InputBridgeDataRoot)
    if(!(Test-Path -LiteralPath $root)){[IO.Directory]::CreateDirectory($root,$security)|Out-Null}else{Set-Acl -LiteralPath $root -AclObject $security}
    foreach($relative in @('Common.ps1','Maintenance.ps1','Lifecycle.ps1','Uninstall.ps1','EmergencyRecover.ps1','FinalizeUninstall.ps1','Recovery\InputBridgeRecovery.exe','Recovery\RecoveryBinding.dll','Payload\InputBridgeExample.exe')){
        $source=Join-Path $PSScriptRoot $relative;$target=Join-Path $root $relative
        [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target))|Out-Null
        if([IO.Path]::GetFullPath($source) -ine [IO.Path]::GetFullPath($target)){Copy-Item -LiteralPath $source -Destination $target -Force}
    }
    if(!$existing){New-Service -Name WindowsKeyboardMouseBridgeRecovery -DisplayName 'InputBridge emergency recovery' -BinaryPathName ('"'+(Join-Path $root 'Recovery\InputBridgeRecovery.exe')+'"') -StartupType Automatic -DependsOn Winmgmt|Out-Null}
    # Automatic start at next boot, never during an installation's mutex hold.
}
function Stop-InputBridgeRecovery {
    $service=Get-Service -Name WindowsKeyboardMouseBridgeRecovery -ErrorAction SilentlyContinue
    if($service){try{if($service.Status -ne 'Stopped'){$service.Stop();$service.WaitForStatus('Stopped',[TimeSpan]::FromSeconds(35))}}finally{$service.Dispose()}}
}
function Remove-InputBridgeRecoveryService {
    Stop-InputBridgeRecovery
    if(Test-Path -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Services\WindowsKeyboardMouseBridgeRecovery'){
        $result=Invoke-InputBridgeProcess (Get-InputBridgeWindowsTool 'sc.exe') @('delete','WindowsKeyboardMouseBridgeRecovery') -TimeoutMs 30000
        if($result.ExitCode -notin @(0,1060,1072)){throw ('Recovery service deletion failed: '+$result.ExitCode)}
        $script:InputBridgeNeedsReboot=$script:InputBridgeNeedsReboot -or $result.ExitCode -eq 1072
    }
}
function Remove-InputBridgeOwnedTree([string]$Path,[string]$Expected) {
    $target=Assert-InputBridgeDirectory $Path $Expected
    if(!(Test-Path -LiteralPath $target)){return}
    $pending=New-Object Collections.Generic.Stack[string];$pending.Push($target)
    while($pending.Count){foreach($item in Get-ChildItem -LiteralPath $pending.Pop() -Force){
        if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw ('Refusing cleanup through reparse point: '+$item.FullName)}
        if($item.PSIsContainer){$pending.Push($item.FullName)}
    }}
    Remove-Item -LiteralPath $target -Recurse -Force
}
function Register-InputBridgeFinalCleanup {
    Get-InputBridgeFinalCleanupTask|Out-Null
    $root=Get-InputBridgeRecoveryRoot
    if(!(Test-Path -LiteralPath (Join-Path $root 'FinalizeUninstall.ps1'))){Install-InputBridgeRecovery}
    $action=New-ScheduledTaskAction -Execute (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe') -Argument ('-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+(Join-Path $root 'FinalizeUninstall.ps1')+'"')
    $trigger=New-ScheduledTaskTrigger -AtStartup
    $settings=New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit ([TimeSpan]::FromMinutes(10)) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    Register-ScheduledTask -TaskName 'WindowsKeyboardMouseBridgeCompleteUninstall' -Action $action -Trigger $trigger -Settings $settings -User 'S-1-5-18' -RunLevel Highest -Force|Out-Null
}
function Remove-InputBridgeFinalCleanup {
    if(Get-InputBridgeFinalCleanupTask){Unregister-ScheduledTask -TaskName WindowsKeyboardMouseBridgeCompleteUninstall -Confirm:$false}
}
function Get-InputBridgeFinalCleanupTask {
    $task=Get-ScheduledTask -TaskName WindowsKeyboardMouseBridgeCompleteUninstall -ErrorAction SilentlyContinue
    if(!$task){return $null}
    $expectedExecute=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $expectedArguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+(Join-Path (Get-InputBridgeRecoveryRoot) 'FinalizeUninstall.ps1')+'"'
    $isSystem=$false
    try{
        $id=[string]$task.Principal.UserId
        $sid=if($id -match '^S-1-') {New-Object Security.Principal.SecurityIdentifier($id)}else{(New-Object Security.Principal.NTAccount($id)).Translate([Security.Principal.SecurityIdentifier])}
        $isSystem=$sid.Value -eq 'S-1-5-18'
    }catch{$isSystem=$false}
    if(@($task.Actions).Count -ne 1 -or $task.Actions[0].Execute -ine $expectedExecute -or $task.Actions[0].Arguments -cne $expectedArguments -or !$isSystem){throw 'An unrelated scheduled task uses the InputBridge cleanup name; it will not be changed.'}
    return $task
}
function Invoke-InputBridgeCleanUninstall([switch]$Finalize) {
    Import-InputBridgeRecoveryAssembly
    Stop-InputBridgeRecovery
    $state=Read-InputBridgeState
    $reboot=$false
    if($state){
        $saved=[InputBridgeRecovery.Devices]::Read((ConvertTo-Json -InputObject @($state.Devices) -Depth 10))
        $owned=@{};foreach($current in [InputBridgeRecovery.Devices]::Snapshot()){if($current.Service -eq 'WindowsKeyboardMouseBridge'){$owned[$current.Instance]=$true}}
        foreach($device in $saved){if($owned.ContainsKey($device.Instance) -and $device.Service -in @('kbdhid','mouhid')){
            try{$reboot=[InputBridgeRecovery.Devices]::RestoreMapper($device,(Join-Path $PSScriptRoot 'Recovery\RecoveryBinding.dll')) -or $reboot}
            catch{Write-Host ('Original binding unavailable; restoring the Windows mapper: '+$device.Instance+'; '+$_.Exception.Message)}
        }}
    }
    Set-InputBridgePhase 'Restore original Windows input bindings'
    $helper=Join-Path $PSScriptRoot 'Payload\InputBridgeExample.exe'
    $restore=Invoke-InputBridgeSetupHelper $helper @('--restore')
    if($restore -notin @(0,3010)){throw ("Windows input restoration failed ("+$restore+"). Recovery files retained.")}
    $reboot=$reboot -or $restore -eq 3010
    if($state){foreach($device in $saved){[InputBridgeRecovery.Devices]::RestoreFilter($device.Instance,$device.Upper);[InputBridgeRecovery.Devices]::RestoreFilter($device.Instance,$device.Lower)}}
    $reboot=[InputBridgeRecovery.Devices]::CleanClassFilters() -or $reboot
    # Pending devnode restarts are not proof that old stacks stopped using
    # the image. Preserve packages and recovery until a normal Windows boot.
    $owned=Get-InputBridgeSetupState $helper
    if($reboot -or @($owned.devices).Count){
        return Set-InputBridgeUninstallPending $state -Finalize:$Finalize
    }
    Set-InputBridgePhase 'Remove unbound owned driver packages'
    foreach($package in Get-InputBridgePackages){Remove-InputBridgePackage $package.Driver}
    $reboot=$reboot -or $script:InputBridgeNeedsReboot
    $remaining=@(Get-InputBridgePackages)
    $driver=Get-Service -Name WindowsKeyboardMouseBridge -ErrorAction SilentlyContinue
    if($driver){$running=$driver.Status -ne 'Stopped';$driver.Dispose();$delete=Invoke-InputBridgeProcess (Get-InputBridgeWindowsTool 'sc.exe') @('delete','WindowsKeyboardMouseBridge') -TimeoutMs 30000;if($delete.ExitCode -notin @(0,1060,1072)){throw ('Driver service removal failed: '+$delete.ExitCode)};$reboot=$reboot -or $running -or $delete.ExitCode -eq 1072}
    if($remaining.Count){$reboot=$true}
    if($state){foreach($cert in $state.CertificatesAdded){
        if($cert.Store -notin @('Root','TrustedPublisher') -or $cert.Thumbprint -notmatch '^[A-Fa-f0-9]{40}$'){throw 'Invalid certificate restoration entry.'}
        $path='Cert:\LocalMachine\'+$cert.Store+'\'+$cert.Thumbprint
        if(Test-Path -LiteralPath $path){Remove-Item -LiteralPath $path}
    }}
    Remove-InputBridgeRecoveryService
    if($reboot -or $script:InputBridgeNeedsReboot){return Set-InputBridgeUninstallPending $state -Finalize:$Finalize}
    Remove-InputBridgeFinalCleanup
    return 0
}

function Set-InputBridgeUninstallPending($State,[switch]$Finalize) {
    if(!$State){$State=[pscustomobject]@{Schema=1;Devices=@();CertificatesAdded=@();PendingUninstall=$true;FinalizeAttempts=0}}
    $State.PendingUninstall=$true
    if($Finalize){
        $State.FinalizeAttempts++
        if($State.FinalizeAttempts -gt 3){Write-InputBridgeState $State;throw 'Cleanup is still pending after three boots; recovery state is retained for diagnosis.'}
    }else{$State.FinalizeAttempts=0}
    Write-InputBridgeState $State
    Register-InputBridgeFinalCleanup
    Write-Host 'Input restoration or package removal requires a restart. Remaining packages and recovery are retained for automatic cleanup after the next normal boot.'
    return 3010
}
