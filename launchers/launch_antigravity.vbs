Set WshShell = CreateObject("WScript.Shell")
WshShell.Run "schtasks.exe /run /tn ""Launch_Antigravity_Elevated""", 0, False
