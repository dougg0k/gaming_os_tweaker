<#
	WIP (not done)

	I might have disabled a service or it's because I am using Win11 22H2 and the tool are not working, I am unable to run RWEverything to test/check if it's correct and finish the script. And I have AMD, so unless there is a proper value or it's the same value, then no way to test for sure.

	https://www.powershellgallery.com/packages/PSMemory/1.0.0/Content/PSMemory.psm1

	Get Hex 18 value 16bit decimal and sum 24 to it, append as the last 4 digits, be sure to be 4 digits even if start with 1 or more zeroes.
	Unsure if the 24 are Intel only and if the right place in memory is the the same or not for AMD.
	I could try to dump a temp file with the mem, it would be 8bit but not problem, get the right value as 16bit and remove after. A 32bit size is enough to dump.

	-------------------------

	Automated script to disable interrupt moderation / coalesting in all usb controllers

	https://www.overclock.net/threads/usb-polling-precision.1550666/page-61
	https://github.com/djdallmann/GamingPCSetup/tree/master/CONTENT/RESEARCH/PERIPHERALS#universal-serial-bus-usb
	https://github.com/BoringBoredom/PC-Optimization-Hub/blob/main/content/xhci%20imod/xhci%20imod.md

	-------------------------

	In case you get problems running the script in Win11, you can run the command to allow, and after, another to set back to a safe or undefined policy

	You can check the current policy settings
	Get-ExecutionPolicy -List

	Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope CurrentUser -Confirm:$false -Force
	Set-ExecutionPolicy -ExecutionPolicy Undefined -Scope CurrentUser -Confirm:$false -Force
#>

# Start as administrator
if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
	Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs; exit
}

# Startup command is optional, because before that you must test the script if will work and not cause BSOD, by not having the startup set, a simple restart should be enough to have it normalized.
# If you want to execute startup script, change from $false to $true
$taskName = "InterruptModerationUsb"
$taskExists = Get-ScheduledTask | Where-Object {$_.TaskName -like $taskName }
if (!$taskExists -And $false) {
  $action = New-ScheduledTaskAction -Execute "powershell" -Argument "-WindowStyle hidden -ExecutionPolicy Bypass -File $PSScriptRoot\interrupt_moderation_usb.ps1"
	$delay = New-TimeSpan -Seconds 10
	$trigger = New-ScheduledTaskTrigger -AtLogOn -RandomDelay $delay
	$principal = New-ScheduledTaskPrincipal -UserID "LOCALSERVICE" -RunLevel Highest
	Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal
	[Environment]::NewLine

	# In case you have to remove the script from startup, but are not able to do from the UI, run:
	# Unregister-ScheduledTask -TaskName "InterruptModerationUsb"
}

Write-Host "Started disabling interrupt moderation in all usb controllers"
[Environment]::NewLine

Remove-Item -Path "HKCU:\SOFTWARE\RW-Everything" -Recurse -ErrorAction Ignore

# REGs improve tools compatibility with Win11 - You might need to reboot to take effect
$BuildNumber = Get-WMIObject Win32_OperatingSystem | Select -ExpandProperty BuildNumber
if ($BuildNumber -ge 22000) {
	Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity" -Name "Enabled" -Value 0 -Force -Type Dword -ErrorAction Ignore
	Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios" -Name "HypervisorEnforcedCodeIntegrity" -Value 0 -Force -Type Dword -ErrorAction Ignore
	Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard" -Name "EnableVirtualizationBasedSecurity" -Value 0 -Force -Type Dword -ErrorAction Ignore
	Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\SystemGuard" -Name "Enabled" -Value 0 -Force -Type Dword -ErrorAction Ignore
	Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\CI\Config" -Name "VulnerableDriverBlocklistEnable" -Value 0 -Force -Type Dword -ErrorAction Ignore
}

[PsObject[]]$USBControllersAddresses = @()

$allUSBControllers = Get-CimInstance -ClassName Win32_PnPEntity | Where-Object { $_.Name -match 'USB' -and $_.Name -match 'Controller'} | Select-Object -Property Name, DeviceID
foreach ($usbController in $allUSBControllers) {
	$allocatedResource = Get-CimInstance -ClassName Win32_PNPAllocatedResource | Where-Object { $_.Dependent.DeviceID -like "*$($usbController.DeviceID)*" } | Select @{N="StartingAddress";E={$_.Antecedent.StartingAddress}}
	$deviceMemory = Get-CimInstance -ClassName Win32_DeviceMemoryAddress | Where-Object { $_.StartingAddress -eq "$($allocatedResource.StartingAddress)" }

	$deviceProperties = Get-PnpDeviceProperty -InstanceId $usbController.DeviceID
	$locationInfo = $deviceProperties | Where KeyName -eq 'DEVPKEY_Device_LocationInfo' | Select -ExpandProperty Data
	$PDOName = $deviceProperties | Where KeyName -eq 'DEVPKEY_Device_PDOName' | Select -ExpandProperty Data

	$USBControllersAddresses += [PsObject]@{
		Name = $usbController.Name
		DeviceId = $usbController.DeviceID
		MemoryRange = $deviceMemory.Name
		LocationInfo = $locationInfo
		PDOName = $PDOName
	}
}

foreach ($item in $USBControllersAddresses) {
	if ([string]::IsNullOrWhiteSpace($item.MemoryRange)) {
		continue
	}
	$LeftSideMemoryRange = $item.MemoryRange.Split("-")[0]
	$Address = ''
	if ($item.Name.Contains('Intel')) {
		$leftWithoutLast4Digits = $LeftSideMemoryRange.Substring(0, $LeftSideMemoryRange.length - 4)
		$Address = $leftWithoutLast4Digits + 2024
	}
	if ($item.Name.Contains('AMD')) {
		# TODO
	}
	if (![string]::IsNullOrWhiteSpace($Address)) {
		..\tools\RW\Rw.exe /Min /NoLogo /Stdout /Stderr /Command="W16 $Address 0x0000"

		$deviceIdMinInfo = $item.DeviceId.Split("\")[1].Split("&")
		$deviceIdVENValue = $deviceIdMinInfo[0].Split("_")[1]
		$deviceIdDEVValue = $deviceIdMinInfo[1].Split("_")[1]
		$VendorId = "0x" + $deviceIdDEVValue + $deviceIdVENValue

		Write-Host "Device: $($item.Name)"
		Write-Host "Device ID: $($item.DeviceId)"
		Write-Host "Location Info: $($item.LocationInfo)"
		Write-Host "PDO Name: $($item.PDOName)"
		Write-Host "Vendor ID: $VendorId"
		Write-Host "Memory Range: $($item.MemoryRange)"
		Write-Host "Address Used: $Address"
		[Environment]::NewLine
		Start-Sleep -Seconds 2
	}
}

cmd /c pause
