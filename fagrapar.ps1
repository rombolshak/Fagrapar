Param(
	[Parameter(Mandatory=$true)][string]$InputFile,
	[string]$OutputFile = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "results.csv")),
	[string]$Proxy = $null)

Set-StrictMode -Version "3.0"	
$ErrorActionPreference = "Stop"
Import-Module $PSScriptRoot\SplitPipeline

function ProcessLink($uri, $proxy, $output)
{
    try 
    {
        Invoke-WebRequest -Uri $uri -Proxy $proxy -ProxyUseDefaultCredentials `
        | ConvertFrom-Json `
        | Export-Csv -Encoding UTF8 -NoTypeInformation -Path $output -Append
    }
    catch
    {
        Write-Host "$($_.Exception.Message) URI: $($uri.Substring(0, 50))..."
    }
}


if (-not (Test-Path $InputFile))
{
    throw "No such file: $InputFile"
}

if (Test-Path $OutputFile)
{
    Write-Host 'Output file is already exists.'
    Write-Host 'Do you want to clear it?'
    Write-Host '[Y] Yes, remove old output and make a new one'
    Write-Host '[N] No, keep existing file and append new results to it'
    Write-Host '[C] Cancel script, I will take care manually'
    $decision = Read-Host "Your choice (default is N)"
    if ($decision -eq 'Y') 
    {
        Write-Host "Clearing file"
        rm $OutputFile
    } 
    elseif ($decision -eq 'C') 
    {
      Write-Host 'Cancelled'
      exit
    }
}

Write-Host Output file is $OutputFile
$links = Get-Content $InputFile
$data = @{
    proxy=$Proxy; 
    output = $OutputFile;
    done = 0;
    total = $links.Count;
}

$links | Split-Pipeline -Variable data -Script `
{process{ 
    $uri = $_
    try 
    {
        Invoke-WebRequest -Uri $uri -Proxy $data.proxy -ProxyUseDefaultCredentials `
        | ConvertFrom-Json `
        | Export-Csv -Encoding UTF8 -NoTypeInformation -Path $data.output -Append
    }
    catch
    {
        Write-Host "$($_.Exception.Message) URI: $($uri.Substring(0, 50))..."
    }
    finally
    {
        [System.Threading.Monitor]::Enter($data)
	    try { $done = ++$data.Done }
	    finally {[System.Threading.Monitor]::Exit($data)}
        Write-Progress -Activity "Done $done" -Status Processing -PercentComplete (100*$done/$data.total)
    }
}}