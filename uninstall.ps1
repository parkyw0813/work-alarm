# 시작 프로그램·시작 메뉴에서 빼고, 실행 중인 알리미 종료
$lnk = Join-Path ([Environment]::GetFolderPath('Startup')) '출퇴근 알리미.lnk'
if (Test-Path $lnk) { Remove-Item $lnk -Force }
$menuLnk = Join-Path ([Environment]::GetFolderPath('Programs')) '출퇴근 알리미.lnk'
if (Test-Path $menuLnk) { Remove-Item $menuLnk -Force }
Remove-Item 'HKCU:\Software\Classes\AppUserModelId\WorkAlarm.Notifier' -Recurse -Force -ErrorAction SilentlyContinue

Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -like '*work-alarm.ps1*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force }

Write-Host '제거 완료.'
