<#
	Automated script to disable Interrupt Moderation (XHCI) or Interrupt Threshold Control (EHCI) in all USB controllers.

	https://www.overclock.net/threads/usb-polling-precision.1550666/page-61
	https://github.com/djdallmann/GamingPCSetup/tree/master/CONTENT/RESEARCH/PERIPHERALS#universal-serial-bus-usb
	https://github.com/BoringBoredom/PC-Optimization-Hub/blob/main/content/xhci%20imod/xhci%20imod.md
	https://linustechtips.com/topic/1477802-what-does-changing-driver-interrupt-affinity-cause-the-driver-to-do/
	https://www.overclock.net/threads/usb-polling-precision.1550666/page-61#post-28580928
	https://github.com/djdallmann/GamingPCSetup/issues/12
	https://www.overclock.net/threads/usb-polling-precision.1550666/page-61#post-28582024
	http://rweverything.com/
	https://github.com/Faintsnow/HE

	Note1: RW command will not run if you have the GUI version open.
	Note2: You should be able to run this script through cmd, powershell or UI, as long as you have downloaded the gaming_os_tweaks folder and are keeping the file in the folder that it belongs.

	Credits to @BoringBoredom, @amitxv and @djdallmann for helping in different ways.

	-------------------------

	Changes made into memory will reset after a simple reboot in the system.

	I created a way to persist the change. You can set this script to be run in every startup automatically.

	Startup script is optional at first, because before that, you must test the script if will work and not cause any BSOD, by not having the startup set, a simple restart should be enough to have it normalized.

	Know that once you have uncommented the startup function call, you must keep the file and folder including everything in the same location that you executed this script file from.

	Go to the bottom of the file and uncoment Apply-Startup-Script, meaning remove the # from before it and run the script again. That should do it.

	-------------------------

	In case you get problems running the script in Win11, you can run the command to allow, and after, another to set back to a safer or undefined policy. But if you have set to be run at every startup, you might want to keep the bypass without changing it back.

	You can check the current policy settings
	Get-ExecutionPolicy -List

	Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope CurrentUser -Confirm:$false -Force
	Set-ExecutionPolicy -ExecutionPolicy Undefined -Scope CurrentUser -Confirm:$false -Force
#>

# Start as administrator
if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
	Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs; exit
}

$RWPath = "$(Split-Path -Path $PSScriptRoot -Parent)\tools\RW"

function Apply-Startup-Script {
	$taskName = "InterruptModerationUsb"
	$taskExists = Get-ScheduledTask | Where-Object {$_.TaskName -like $taskName }
	if (!$taskExists) {
		$action = New-ScheduledTaskAction -Execute "powershell" -Argument "-WindowStyle hidden -ExecutionPolicy Bypass -File $PSScriptRoot\interrupt_moderation_usb.ps1"
		$delay = New-TimeSpan -Seconds 10
		$trigger = New-ScheduledTaskTrigger -AtLogOn -RandomDelay $delay
		$principal = New-ScheduledTaskPrincipal -UserID "LOCALSERVICE" -RunLevel Highest
		$STSet = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 3)
		Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $STSet
		[Environment]::NewLine

		# In case you have to remove the script from startup, but are not able to do from the UI, run:
		# Unregister-ScheduledTask -TaskName "InterruptModerationUsb"
	}
}

function Apply-Tool-Compatibility-Registries {
	$BuildNumber = Get-WMIObject Win32_OperatingSystem | Select -ExpandProperty BuildNumber
	$isWin11 = $BuildNumber -ge 22000
	if ($isWin11) {
		Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity" -Name "Enabled" -Value 0 -Force -Type Dword -ErrorAction Ignore
		Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios" -Name "HypervisorEnforcedCodeIntegrity" -Value 0 -Force -Type Dword -ErrorAction Ignore
		Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard" -Name "EnableVirtualizationBasedSecurity" -Value 0 -Force -Type Dword -ErrorAction Ignore
		Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\SystemGuard" -Name "Enabled" -Value 0 -Force -Type Dword -ErrorAction Ignore
		Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\CI\Config" -Name "VulnerableDriverBlocklistEnable" -Value 0 -Force -Type Dword -ErrorAction Ignore
	}
}

function Get-All-USB-Controllers {
	[PsObject[]]$USBControllers= @()

	$allUSBControllers = Get-CimInstance -ClassName Win32_USBController | Select-Object -Property Name, DeviceID
	foreach ($usbController in $allUSBControllers) {
		$allocatedResource = Get-CimInstance -ClassName Win32_PNPAllocatedResource | Where-Object { $_.Dependent.DeviceID -like "*$($usbController.DeviceID)*" } | Select @{N="StartingAddress";E={$_.Antecedent.StartingAddress}}
		$deviceMemory = Get-CimInstance -ClassName Win32_DeviceMemoryAddress | Where-Object { $_.StartingAddress -eq "$($allocatedResource.StartingAddress)" }

		$deviceProperties = Get-PnpDeviceProperty -InstanceId $usbController.DeviceID
		$locationInfo = $deviceProperties | Where KeyName -eq 'DEVPKEY_Device_LocationInfo' | Select -ExpandProperty Data
		$PDOName = $deviceProperties | Where KeyName -eq 'DEVPKEY_Device_PDOName' | Select -ExpandProperty Data

		$moreControllerData = Get-CimInstance -ClassName Win32_PnPEntity | Where-Object { $_.DeviceID -eq "$($usbController.DeviceID)" } | Select-Object Service
		$Type = Get-Type-From-Service -value $moreControllerData.Service

		if ([string]::IsNullOrWhiteSpace($deviceMemory.Name)) {
			continue
		}

		$USBControllers += [PsObject]@{
			Name = $usbController.Name
			DeviceId = $usbController.DeviceID
			MemoryRange = $deviceMemory.Name
			LocationInfo = $locationInfo
			PDOName = $PDOName
			Type = $Type
		}
	}
	return $USBControllers
}

function Get-Type-From-Service {
	param ([string] $value)
	if ($value -ieq 'USBXHCI') {
		return 'XHCI'
	}
	if ($value -ieq 'USBEHCI') {
		return 'EHCI'
	}
	return 'Unknown'
}

function Convert-Decimal-To-Hex {
	param ([int64] $value)
	return '0x' + [System.Convert]::ToString($value, 16).ToUpper()
}

function Convert-Hex-To-Decimal {
	param ([string] $value)
	return [convert]::ToInt64($value, 16)
}

function Convert-Hex-To-Binary {
	param ([string] $value)
	$ConvertedValue = [Convert]::ToString($value, 2)
	return $ConvertedValue.PadLeft(32, '0')
}

function Convert-Binary-To-Hex {
	param ([string] $value)
	$convertedValue = [Convert]::ToInt64($value, 2)
	return Convert-Decimal-To-Hex -value $convertedValue
}

function Get-Hex-Value-From-RW-Result {
	param ([string] $value)
	return $value.Split("=")[1].Trim()
}

function Get-R32-Hex-From-Address {
	param ([string] $address)
	$Value = & "$RWPath\Rw.exe" /Min /NoLogo /Stdout /Command="R32 $address" 2>&1 | Out-String
	while ([string]::IsNullOrWhiteSpace($Value)) { Start-Sleep -Seconds 1 }
	return Get-Hex-Value-From-RW-Result -value $Value
}

function Clean-Up {
	Stop-Process -Name Rw.exe -Force -ErrorAction Ignore
	Remove-Item -Path "HKCU:\SOFTWARE\RW-Everything" -Recurse -ErrorAction Ignore
}

function Get-Left-Side-From-MemoryRange {
	param ([string] $memoryRange)
	return $memoryRange.Split("-")[0]
}

function Get-BitRange-From-Binary {
	param ([string] $binaryValue, [int] $from, [int] $to)
	$backwardsFrom = $to
	$backwardsTo = $from
	return $binaryValue.SubString($binaryValue.Length - $backwardsFrom, $backwardsFrom - $backwardsTo)
}

function Get-VendorId {
	param ([string] $deviceId)
	if ([string]::IsNullOrWhiteSpace($deviceId)) {
		return "None"
	}
	$deviceIdMinInfo = $deviceId.Split("\")[1].Split("&")
	$deviceIdVENValue = $deviceIdMinInfo[0].Split("_")[1]
	$deviceIdDEVValue = $deviceIdMinInfo[1].Split("_")[1]
	return "0x" + $deviceIdDEVValue + $deviceIdVENValue
}

function Find-First-Interrupter-Data {
	param ([string] $memoryRange)
	$LeftSideMemoryRange = Get-Left-Side-From-MemoryRange -memoryRange $memoryRange
	$CapabilityBaseAddressInDecimal = Convert-Hex-To-Decimal -value $LeftSideMemoryRange
	$RuntimeRegisterSpaceOffsetInDecimal = Convert-Hex-To-Decimal -value "0x18"
	$SumCapabilityPlusRuntime = Convert-Decimal-To-Hex -value ($CapabilityBaseAddressInDecimal + $RuntimeRegisterSpaceOffsetInDecimal)
	$Value = Get-R32-Hex-From-Address -address $SumCapabilityPlusRuntime
	$ValueInDecimal = Convert-Hex-To-Decimal -value $Value
	$TwentyFourInDecimal = Convert-Hex-To-Decimal -value "0x24"
	$Interrupter0PreAddressInDecimal = $CapabilityBaseAddressInDecimal + $ValueInDecimal + $TwentyFourInDecimal

	$FourInDecimal = Convert-Hex-To-Decimal -value "0x4"
	$HCSPARAMS1InHex = Convert-Decimal-To-Hex -value ($CapabilityBaseAddressInDecimal + $FourInDecimal)

	return @{ Interrupter0PreAddressInDecimal = $Interrupter0PreAddressInDecimal; HCSPARAMS1 = $HCSPARAMS1InHex }
}

function Build-Interrupt-Threshold-Control-Data {
	param ([string] $memoryRange)
	$LeftSideMemoryRange = Get-Left-Side-From-MemoryRange -memoryRange $memoryRange
	$LeftSideMemoryRangeInDecimal = Convert-Hex-To-Decimal -value $LeftSideMemoryRange
	$TwentyInDecimal = Convert-Hex-To-Decimal -value "0x20"
	$MemoryBase = Convert-Decimal-To-Hex -value ($LeftSideMemoryRangeInDecimal + $TwentyInDecimal)
	$MemoryBaseValue = Get-R32-Hex-From-Address -address $MemoryBase
	$ValueInBinary = Convert-Hex-To-Binary -value $MemoryBaseValue
	$ReplaceValue = '00000000'
	$BackwardsFrom = 16
	$BackwardsTo = 23
	$ValueInBinaryLeftSide = $ValueInBinary.Substring(0, $ValueInBinary.Length - $BackwardsTo)
	$ValueInBinaryRightSide = $ValueInBinary.Substring($ValueInBinary.Length - $BackwardsTo + $ReplaceValue.Length, ($ValueInBinary.Length - 1) - $BackwardsFrom)
	$ValueAddress = Convert-Binary-To-Hex -value ($ValueInBinaryLeftSide + $ReplaceValue + $ValueInBinaryRightSide)
	return [PsObject]@{ValueAddress = $ValueAddress; InterruptAddress = $MemoryBase}
}

function Find-Interrupters-Amount {
	param ([string] $hcsParams1)
	$Value = Get-R32-Hex-From-Address -address $hcsParams1
	$ValueInBinary = Convert-Hex-To-Binary -value $Value
	$MaxIntrsInBinary = Get-BitRange-From-Binary -binaryValue $ValueInBinary -from 8 -to 18
	$InterruptersAmount = Convert-Hex-To-Decimal -value (Convert-Binary-To-Hex -value $MaxIntrsInBinary)
	return $InterruptersAmount
}

function Disable-IMOD {
	param ([string] $address, [string] $value)
	$valueData = if ([string]::IsNullOrWhiteSpace($value)) { return '0x00000000' } else { return $value }
	$Value = & "$RWPath\Rw.exe" /Min /NoLogo /Stdout /Command="W32 $address $valueData" 2>&1 | Out-String
	while ([string]::IsNullOrWhiteSpace($Value)) { Start-Sleep -Seconds 1 }
}

function Get-All-Interrupters {
	param ([int64] $preAddressInDecimal, [int32] $interruptersAmount)
	[PsObject[]]$Data = @()
	if ($interruptersAmount -lt 1 -or $interruptersAmount -gt 1024) {
		Write-Host "Device interrupters amount is different than specified - $interruptersAmount - No address from this device were IMOD disabled"
		return $Data
	}
	for ($i=0; $i -lt $interruptersAmount; $i++) {
		$AddressInDecimal = $preAddressInDecimal + (32 * $i)
		$InterrupterAddress = Convert-Decimal-To-Hex -value $AddressInDecimal
		$Address = Get-R32-Hex-From-Address -address $InterrupterAddress
		$Data += [PsObject]@{ValueAddress = $Address; InterrupterAddress = $InterrupterAddress; Interrupter = $i}
	}
	return $Data
}

function Execute-IMOD-Process {
	Write-Host "Started disabling Interrupt Moderation (XHCI) or Interrupt Threshold Control (EHCI) in all USB controllers"
	[Environment]::NewLine

	$USBControllers = Get-All-USB-Controllers

	if ($USBControllers.Length -eq 0) {
		Write-Host "Script didnt found any valid USB controllers to be disabled, try opening an issue at the same place you got this script from, take screenshot(s) from all your usb controllers at device manager or some place else you might know how to get, and use as feedback."
	} else {
		Write-Host "------------------------------------------------------------------"
	}
	[Environment]::NewLine

	foreach ($item in $USBControllers) {
		$InterruptersAmount = 'None'
		if ($item.Type -eq 'XHCI') {
			$FirstInterrupterData = Find-First-Interrupter-Data -memoryRange $item.MemoryRange
			$InterruptersAmount = Find-Interrupters-Amount -hcsParams1 $FirstInterrupterData.HCSPARAMS1
			$AllInterrupters = Get-All-Interrupters -preAddressInDecimal $FirstInterrupterData.Interrupter0PreAddressInDecimal -interruptersAmount $InterruptersAmount

			foreach ($interrupterItem in $AllInterrupters) {
				Disable-IMOD -address $interrupterItem.ValueAddress
				Write-Host "Disabled IMOD - Interrupter $($interrupterItem.Interrupter) - Interrupter Address $($interrupterItem.InterrupterAddress) - Value Address $($interrupterItem.ValueAddress)"
			}
		}
		if ($item.Type -eq 'EHCI') {
			$InterruptData = Build-Interrupt-Threshold-Control-Data -memoryRange $item.MemoryRange
			Disable-IMOD -address $InterruptData.InterruptAddress -value $InterruptData.ValueAddress
			Write-Host "Disabled Interrupt Threshold Control - Interrupt Address $($InterruptData.InterruptAddress) - Value Address $($InterruptData.ValueAddress)"
		}

		[Environment]::NewLine
		$VendorId = Get-VendorId -deviceId $item.DeviceId
		Write-Host "Device: $($item.Name)"
		Write-Host "Device ID: $($item.DeviceId)"
		Write-Host "Location Info: $($item.LocationInfo)"
		Write-Host "PDO Name: $($item.PDOName)"
		Write-Host "Vendor ID: $VendorId"
		Write-Host "Device Type: $($item.Type)"
		Write-Host "Memory Range: $($item.MemoryRange)"
		Write-Host "Interrupters Count: $InterruptersAmount"
		[Environment]::NewLine
		Write-Host "------------------------------------------------------------------"
		[Environment]::NewLine
	}

}

# --------------------------------------------------------------------------------------------

# Uncomment line below if you want to apply startup script
# Apply-Startup-Script

# REGs to improve tools compatibility with Win11 - You might need to reboot to take effect
Apply-Tool-Compatibility-Registries

Clean-Up

Execute-IMOD-Process

Clean-Up

cmd /c pause
