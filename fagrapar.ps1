Param(
	[Parameter(Mandatory=$true)][string]$InputFile,
	[string]$OutputFile = "results.csv",
	[string]$Proxy = $null)

Set-StrictMode -Version "3.0"	
$ErrorActionPreference = "Stop"


if (-not (Test-Path $InputFile))
{
    throw "No such file: $InputFile"
}

$links = Get-Content $InputFile

$resultFile = New-Item -Path $PSScriptRoot -Name $OutputFile -ItemType File -Force 

Write-Host "Total $($links.Length) links"