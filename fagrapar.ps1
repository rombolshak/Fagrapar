Param(
	[Parameter(Mandatory=$true)][string]$InputFile,
	[Parameter(Mandatory=$true)][string]$Proxy = $null,
	[string]$OutputFile = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "results.csv")),
    [switch]$JustCollectResults)

Set-StrictMode -Version "3.0"	
$ErrorActionPreference = "Stop"
Import-Module $PSScriptRoot\SplitPipeline

$resultsDirectory = New-Item `
    -Name ([System.IO.Path]::GetFileNameWithoutExtension($OutputFile)) `
    -Path ([System.IO.Path]::GetDirectoryName($OutputFile)) `
    -ItemType Directory -Force

function CollectResults()
{
    Write-Host "Creaing result file"
    Get-ChildItem $resultsDirectory |% { Import-Csv $_.FullName } | Export-Csv -Encoding UTF8 -NoTypeInformation -Path $OutputFile
    Write-Host "Clear temp results directory"
    Remove-Item $resultsDirectory -Recurse -Force
    Write-Host "Done"
}

if ($JustCollectResults)
{
    CollectResults
    exit
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

$stopwatch = [system.diagnostics.stopwatch]::StartNew()

try
{
    Write-Host Output file is $OutputFile
    $links = Get-Content $InputFile
    $data = @{
        proxy=$Proxy; 
        done = 0;
        failed = 0;
        total = $links.Count;
        currentDir = $PSScriptRoot;
    }

    $links | Split-Pipeline -Variable data, resultsDirectory -Script `
    {process{

        Import-Module "$($data.currentDir)\LockObject"
        . "$($data.currentDir)\ConvertTo-FlatObject.ps1"
        $uri = $_

        try 
        {
            $id = [System.Guid]::NewGuid();
            Invoke-WebRequest -Uri $uri `
                -Proxy $data.proxy -ProxyUseDefaultCredentials `
                | ConvertFrom-Json `
                | ConvertTo-FlatObject `
                | Export-Csv -Encoding UTF8 -NoTypeInformation -Path "$resultsDirectory\$id.csv"
        }
        catch
        {
            Write-Host "$($_.Exception.Message) URI: $($uri.Substring(0, 50))..."
            Lock-Object $data { ++$data.failed }
        }
        finally
        {
            Lock-Object $data { $done = ++$data.done }
            Write-Progress -Activity "Done $done of $($data.total)" -Status Processing -PercentComplete (100*$done/$data.total)
        }
    }}

}
finally
{
    $stopwatch.Stop()
    Write-Host Processed $($data.done - $data.failed) links of $($data.total)
    Write-Host Failed $data.failed "request(s)"
    Write-Host Total time: $($stopwatch.Elapsed)
}

CollectResults