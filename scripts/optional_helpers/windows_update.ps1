# Windows Update through powershell

# Depending on the kind of tweaks you have done, this may or may not work.
# If you have done them all, from all these folders, the cumulatives update will probably fail.

# I dont know all the things in all the tweaks+debloat that would cause this to break, I know you can not have windows update and this would still work.
# If someone want to figure out in the simplest and cleanest way and make a PR.

Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
if (!(Get-Module -Name PSWindowsUpdate)) {
    Install-Module PSWindowsUpdate
    Add-WUServiceManager -MicrosoftUpdate
}

# Get detailed documentations of a module / command. E.g.,
# Get-Help Get-WindowsUpdate -detailed

# If you are getting errors using commands, you need to set a exec policy before, to allow. After you can restrict again.
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force

# -----------------------------------------------------------------------------

# Check available updates
# Get-WindowsUpdate

# Check Service Ids available
# Get-WUServiceManager

# Enable newest service option
# Add-WUServiceManager -ServiceID "7971f918-a847-4430-9279-4a52d1efe18d" -AddServiceFlag 7

# Install all updates
Install-WindowsUpdate -MicrosoftUpdate -AcceptAll -AutoReboot -Verbose

# Exclude specific updates from installing
# Hide-WindowsUpdate -KBArticleID KB4052623

# Install specific update
# Install-WindowsUpdate -KBArticleID KB2267602

# Remove specific update
# Remove-WindowsUpdate -KBArticleID KB2267602

# Check if update require reboot
# Get-WURebootStatus

# Check update history
# Get-WUHistory

# -------------------------------------------------------------------------------

Set-ExecutionPolicy Restricted -Scope CurrentUser -Force
