# 다른 사람에게 줄 배포 묶음 만들기
# 결과: dist\출퇴근알리미\ 폴더와 dist\출퇴근알리미.zip
# 알리미를 고친 뒤 이걸 다시 돌리면 최신 내용으로 다시 만들어진다.
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$dist = Join-Path $root 'dist'
$out  = Join-Path $dist '출퇴근알리미'
$zip  = Join-Path $dist '출퇴근알리미.zip'

if (Test-Path $out) { Remove-Item $out -Recurse -Force }
if (Test-Path $zip) { Remove-Item $zip -Force }
New-Item -ItemType Directory -Force $out | Out-Null

$bom = New-Object System.Text.UTF8Encoding $true
function Copy-Utf8Bom([string]$from, [string]$to) {
    $t = [IO.File]::ReadAllText($from, [Text.Encoding]::UTF8)
    [IO.File]::WriteAllText($to, $t, $bom)
}

# 알리미 본체 + 사진
Copy-Utf8Bom (Join-Path $root 'work-alarm.ps1') (Join-Path $out 'work-alarm.ps1')
Copy-Item (Join-Path $root 'run-hidden.vbs') $out
Copy-Item (Join-Path $root 'assets') $out -Recurse

# 배포용 설치·제거·사용법
$pkg = Join-Path $root 'package'
Copy-Utf8Bom (Join-Path $pkg 'install.ps1')   (Join-Path $out 'install.ps1')
Copy-Utf8Bom (Join-Path $pkg 'uninstall.ps1') (Join-Path $out 'uninstall.ps1')
Copy-Utf8Bom (Join-Path $pkg '사용법.txt')     (Join-Path $out '사용법.txt')

$ascii = New-Object System.Text.ASCIIEncoding
[IO.File]::WriteAllText((Join-Path $out '설치.bat'), "@echo off`r`npowershell -NoProfile -ExecutionPolicy Bypass -File `"%~dp0install.ps1`"`r`npause`r`n", $ascii)
[IO.File]::WriteAllText((Join-Path $out '제거.bat'), "@echo off`r`npowershell -NoProfile -ExecutionPolicy Bypass -File `"%~dp0uninstall.ps1`"`r`npause`r`n", $ascii)

Compress-Archive -Path $out -DestinationPath $zip
Write-Host "완료: $zip"
