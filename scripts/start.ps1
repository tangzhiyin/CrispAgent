[CmdletBinding()]
param(
    [int]$Port = 8787,
    [string]$Model = "auto",
    [switch]$LocalOnly
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $projectRoot

$env:CRISP_AGENT_PORT = [string]$Port
$env:CRISP_AGENT_MODEL = $Model
$env:CRISP_AGENT_HOST = if ($LocalOnly) { "127.0.0.1" } else { "0.0.0.0" }

npm start
