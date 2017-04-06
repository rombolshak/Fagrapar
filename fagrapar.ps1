Param(
	[Parameter(Mandatory=$true)][string]$InputFile,
	[Parameter(Mandatory=$true)][string]$Proxy = $null,
	[string]$OutputFile = [System.IO.Path]::GetFullPath((Join-Path (Get-Location) "results.csv")),
	[string]$FailedFile = [System.IO.Path]::GetFullPath((Join-Path (Get-Location) "failed.txt")),
	[int]$RetryCount = 1,
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
	Write-Host 'Output file is already exists, it will be rewritten and old results will be deleted'
	Write-Host 'Press Enter to continue or Ctrl+C to cancel'
	Read-Host 
	Remove-Item $OutputFile
	Get-ChildItem $resultsDirectory | Remove-Item -Force
}

$stopwatch = [system.diagnostics.stopwatch]::StartNew()

try
{
	Write-Host Output file is $OutputFile
	$links = Get-Content $InputFile
	$data = @{
		proxy = $Proxy; 
		retryCount = $RetryCount;
		done = 0;
		failed = 0;
		total = $links.Count;
		currentDir = $PSScriptRoot;
	}

	$links | Split-Pipeline -Variable data, resultsDirectory, FailedFile -Script `
	{process{

		Import-Module "$($data.currentDir)\LockObject"
		. "$($data.currentDir)\ConvertTo-FlatObject.ps1"
		$uri = $_
		$attemptNumber = 0
		$success = $false
		$id = [System.Guid]::NewGuid()

		while(-not $success -and $attemptNumber -le $data.retryCount)
		{
			++$attemptNumber;
			try 
			{
				Invoke-WebRequest -Uri $uri `
					-Proxy $data.proxy -ProxyUseDefaultCredentials `
					| ConvertFrom-Json `
					| ConvertTo-FlatObject `
					| Export-Csv -Encoding UTF8 -NoTypeInformation -Path "$resultsDirectory\$id.csv"
				$success = $true
			}
			catch
			{
				Write-Host "Attempt $attemptNumber. $($_.Exception.Message) URI: $($uri.Substring(0, 50))..."
			}
		}

		Lock-Object $data `
		{ 
			$done = ++$data.done
			if (!$success) 
			{
				++$data.failed
				$uri | Out-File $FailedFile -Append
			} 
		}

		Write-Progress -Activity "Done $done of $($data.total)" -Status Processing -PercentComplete (100*$done/$data.total)			
	}}
}
finally
{
	$stopwatch.Stop()
	Write-Host Processed $($data.done - $data.failed) links of $($data.total)
	Write-Host Failed $data.failed "request(s)"
	Write-Host Total time: $($stopwatch.Elapsed)
	
	CollectResults
}
