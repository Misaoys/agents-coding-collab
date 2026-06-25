<#
.SYNOPSIS
    Watch the Agents Coding Collab model trace log.
.DESCRIPTION
    Keeps a PowerShell terminal attached to the shared trace log so future model runs appear
    automatically. This script does not start model calls.
#>
[CmdletBinding()]
param(
    [string]$LogPath = [System.Environment]::GetEnvironmentVariable("AGENTS_CODING_TRACE_LOG"),
    [int]$Tail = 80,
    [switch]$Clear,
    [switch]$Once
)

$ErrorActionPreference = "Stop"
if (-not $LogPath) {
    $LogPath = Join-Path $env:TEMP "agents-coding-collab-model-trace.log"
}

$dir = Split-Path -Parent $LogPath
if ($dir -and -not (Test-Path $dir)) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
}
if ($Clear -and (Test-Path $LogPath)) {
    Remove-Item -LiteralPath $LogPath -Force
}
if (-not (Test-Path $LogPath)) {
    New-Item -ItemType File -Force -Path $LogPath | Out-Null
}

Write-Host "Watching Agents Coding Collab model trace:" -ForegroundColor Cyan
Write-Host "  $LogPath" -ForegroundColor Cyan
Write-Host ""
if ($Once) {
    Get-Content -LiteralPath $LogPath -Tail $Tail -Encoding UTF8
    return
}

Get-Content -LiteralPath $LogPath -Tail $Tail -Wait -Encoding UTF8
