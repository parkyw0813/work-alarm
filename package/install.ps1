# 출퇴근 알리미 설치 (배포용)
# 이 폴더의 파일을 내 PC 개인 폴더(%LOCALAPPDATA%\WorkAlarm\app)로 복사하고,
# 컴퓨터를 켤 때 자동 실행되게 등록한 뒤 바로 실행한다.
$ErrorActionPreference = 'Stop'
try {
    $src = $PSScriptRoot
    $dst = Join-Path $env:LOCALAPPDATA 'WorkAlarm\app'
    $wscript = Join-Path $env:WINDIR 'System32\wscript.exe'

    # 이미 켜져 있으면 끄기 (다시 설치·업데이트할 때)
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
        Where-Object { $_.CommandLine -like '*work-alarm.ps1*' } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force }

    # 파일 복사 (사진 폴더는 새로 바꿔 넣음)
    New-Item -ItemType Directory -Force $dst | Out-Null
    if (Test-Path (Join-Path $dst 'assets')) { Remove-Item (Join-Path $dst 'assets') -Recurse -Force }
    Copy-Item (Join-Path $src 'work-alarm.ps1'), (Join-Path $src 'run-hidden.vbs') $dst -Force
    if (Test-Path (Join-Path $src 'assets')) { Copy-Item (Join-Path $src 'assets') $dst -Recurse -Force }

    # 인터넷·메신저로 받은 파일 표시 풀기 (안 풀면 실행이 막힐 수 있음)
    Get-ChildItem $dst -Recurse -File | Unblock-File

    # 컴퓨터 켤 때 자동 실행
    $vbs = Join-Path $dst 'run-hidden.vbs'
    $lnk = Join-Path ([Environment]::GetFolderPath('Startup')) '출퇴근 알리미.lnk'
    $sh = New-Object -ComObject WScript.Shell
    $s = $sh.CreateShortcut($lnk)
    $s.TargetPath = $wscript
    $s.Arguments = '"' + $vbs + '"'
    $s.WorkingDirectory = $dst
    $s.Description = '컴퓨터 켠 시각 기준 퇴근·점심 알림'
    $s.Save()

    Start-Process $wscript -ArgumentList ('"' + $vbs + '"')

    Write-Host ''
    Write-Host '  설치 완료!' -ForegroundColor Green
    Write-Host '  - 화면 오른쪽 아래 작업표시줄에 시계 아이콘이 생겨요. (안 보이면 ^ 를 눌러 보세요)'
    Write-Host '  - 이제 컴퓨터를 켤 때마다 자동으로 실행돼요.'
    Write-Host '  - 이 설치 폴더는 지워도 괜찮아요.'
    Write-Host ''
} catch {
    Write-Host ''
    Write-Host ('  설치 중 문제가 생겼어요: ' + $_) -ForegroundColor Red
    Write-Host '  이 창을 캡처해서 보내 주세요.'
    Write-Host ''
}
