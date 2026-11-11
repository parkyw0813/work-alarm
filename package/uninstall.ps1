# 출퇴근 알리미 제거 (배포용): 끄고, 자동 실행·시작 메뉴에서 빼고, 설치 파일·기록 삭제
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -like '*work-alarm.ps1*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
Start-Sleep -Milliseconds 500

foreach ($lnk in @(
    (Join-Path ([Environment]::GetFolderPath('Startup')) '출퇴근 알리미.lnk'),
    (Join-Path ([Environment]::GetFolderPath('Programs')) '출퇴근 알리미.lnk')
)) { if (Test-Path $lnk) { Remove-Item $lnk -Force } }

$dir = Join-Path $env:LOCALAPPDATA 'WorkAlarm'
if (Test-Path $dir) { Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue }

Write-Host ''
Write-Host '  제거 완료.' -ForegroundColor Green
Write-Host ''
