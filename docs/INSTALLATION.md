# Windows Keyboard & Mouse Bridge: installation

Version 0.1.0.0 has a verified matching Microsoft-signed package. The [demo ZIP](https://github.com/StrikeFound/Windows-Keyboard-Mouse-Bridge/releases/download/v0.1.0.0/Windows-Keyboard-Mouse-Bridge-0.1.0.0-Demo.zip) contains both installers; the SDK ZIP contains source and the signed binary build inputs. Never rename another edition's driver or disable signature enforcement.

Run `InputBridgeSetup.exe` as administrator and choose Install /
reinstall. Restart when requested. Console automation uses
`InputBridgeSetupConsole.exe /install` or `/uninstall`.

This edition's service is `WindowsKeyboardMouseBridge`. Setup refuses overlapping original/new
input editions and stale filters. Complete their uninstall and restart first.
The keyboard/mouse-only and gamepad-only editions may coexist. The installer
does not remove another product's service or data.

The UI starts observation automatically. Stop or close it to release capture.
One hour after first capture, demo expiry also releases capture to passthrough.
