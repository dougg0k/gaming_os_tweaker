:: Make sure before you run this, to install Winget + OpenShell. Check /optional_helpers/install_apps.cmd
cd %windir%\SystemApps

:: Disable Search
taskkill /f /im SearchApp.exe
taskkill /f /im SearchApp.exe
move Microsoft.Windows.Search_cw5n1h2txyewy Microsoft.Windows.Search_cw5n1h2txyewy.old

:: Disable Start Menu
taskkill /f /im StartMenuExperienceHost.exe
taskkill /f /im StartMenuExperienceHost.exe
move Microsoft.Windows.StartMenuExperienceHost_cw5n1h2txyewy Microsoft.Windows.StartMenuExperienceHost_cw5n1h2txyewy.old

:: Disable Text Input
taskkill /f /im TextInputHost.exe
taskkill /f /im TextInputHost.exe
move MicrosoftWindows.Client.CBS_cw5n1h2txyewy MicrosoftWindows.Client.CBS_cw5n1h2txyewy.old

:: Additionals
move Microsoft.XboxGameCallableUI_cw5n1h2txyewy Microsoft.XboxGameCallableUI_cw5n1h2txyewy.old
move Microsoft.MicrosoftEdgeDevToolsClient_8wekyb3d8bbwe Microsoft.MicrosoftEdgeDevToolsClient_8wekyb3d8bbwe.old
move Microsoft.Windows.PeopleExperienceHost_cw5n1h2txyewy Microsoft.Windows.PeopleExperienceHost_cw5n1h2txyewy.old
move microsoft.windows.narratorquickstart_8wekyb3d8bbwe microsoft.windows.narratorquickstart_8wekyb3d8bbwe.old
