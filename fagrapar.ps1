Param(
	[Parameter(Mandatory=$true)][string]$InputFile,
	[string]$OutputFile = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "results.csv")),
	[string]$Proxy = $null)

Set-StrictMode -Version "3.0"	
$ErrorActionPreference = "Stop"
Import-Module $PSScriptRoot\SplitPipeline

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
    done = 0;
    total = $links.Count;
    currentDir = $PSScriptRoot;
}

$links | Split-Pipeline -Variable data, OutputFile -Verbose -Script `
{process{

    Import-Module "$($data.currentDir)\LockObject"
    function ExecuteInMonitor($lock, [scriptblock]$script)
    {
        [System.Threading.Monitor]::Enter($lock)
        try { &$script }
        finally {[System.Threading.Monitor]::Exit($lock)}
    }

    $uri = $_
    try 
    {
        Invoke-WebRequest -Uri $uri -Proxy $data.proxy -ProxyUseDefaultCredentials `
        | ConvertFrom-Json `
        | Export-Csv -Encoding UTF8 -NoTypeInformation -Path $OutputFile -Append
        Start-Sleep 1000
    }
    catch
    {
        Write-Host "$($_.Exception.Message) URI: $($uri.Substring(0, 50))..."
    }
    finally
    {
        Lock-Object $data { $done = ++$data.Done } -Verbose
        Write-Progress -Activity "Done $done" -Status Processing -PercentComplete (100*$done/$data.total)
    }
}}