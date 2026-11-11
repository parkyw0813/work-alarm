# 시작 프로그램에 등록하고 지금 바로 실행
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$vbs = Join-Path $dir 'run-hidden.vbs'
$lnk = Join-Path ([Environment]::GetFolderPath('Startup')) '출퇴근 알리미.lnk'

$sh = New-Object -ComObject WScript.Shell
$s = $sh.CreateShortcut($lnk)
$s.TargetPath = Join-Path $env:WINDIR 'System32\wscript.exe'
$s.Arguments = '"' + $vbs + '"'
$s.WorkingDirectory = $dir
$s.Description = '컴퓨터 켠 시각 기준 퇴근·점심 알림'
$s.Save()

Start-Process (Join-Path $env:WINDIR 'System32\wscript.exe') -ArgumentList ('"' + $vbs + '"')
Write-Host '등록 완료: 컴퓨터를 켤 때마다 자동으로 실행돼요.'
