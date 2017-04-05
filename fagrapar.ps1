Param(
	[Parameter(Mandatory=$true)][string]$InputFile,
	[string]$OutputFile = "results.csv",
	[string]$Proxy = $null)

Set-StrictMode -Version "3.0"	
$ErrorActionPreference = "Stop"

function GetWebResponse($uri)
{
    $result = Invoke-WebRequest -Uri $uri -Proxy $Proxy -ProxyUseDefaultCredentials | ConvertFrom-Json | Export-Csv -Encoding UTF8 -NoTypeInformation -Path $OutputFile -Append
}


if (-not (Test-Path $InputFile))
{
    throw "No such file: $InputFile"
}

$links = Get-Content $InputFile

$links |% { GetWebResponse $_ }

Write-Host "Total $($links.Length) links"