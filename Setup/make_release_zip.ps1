$ErrorActionPreference = 'Stop'

$packageName = 'SYNC_Motion'
$pluginFile = 'C:\ProgramData\aviutl2\Plugin\SYNC_Motion\SYNC_Motion_Filter.auf2'
$workDir = Join-Path $PSScriptRoot $packageName
$zipFile = Join-Path $PSScriptRoot "$packageName.zip"

if (-not (Test-Path -LiteralPath $pluginFile -PathType Leaf)) {
  Write-Host 'Filter plugin not found:'
  Write-Host "  $pluginFile"
  Write-Host 'Build the Release configuration first, then run this batch again.'
  exit 1
}

if (Test-Path -LiteralPath $workDir) {
  Remove-Item -LiteralPath $workDir -Recurse -Force
}

if (Test-Path -LiteralPath $zipFile) {
  Remove-Item -LiteralPath $zipFile -Force
}

try {
  New-Item -ItemType Directory -Path $workDir -Force | Out-Null
  Copy-Item -LiteralPath $pluginFile -Destination $workDir -Force
  Compress-Archive -Path $workDir -DestinationPath $zipFile -Force
}
finally {
  if (Test-Path -LiteralPath $workDir) {
    Remove-Item -LiteralPath $workDir -Recurse -Force
  }
}

Write-Host 'Created:'
Write-Host "  $zipFile"
