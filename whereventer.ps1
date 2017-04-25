<#
Here it is description of what and how this script do.

For normal use case it should be called in the way below.
. .\whereventer.ps1 -InputFile C:\some\dir\to\file\with\links.txt -Proxy http://proxy.domain.com:8080 
This will generate file named results.csv in current directory. If there were any unsuccessful requests, file failed.txt wll be generated.

If you want another results file, specify it with -OutputFile parameter. 
Example: . .\whereventer.ps1 -InputFile .\links.txt -Proxy http://1.2.3.4:9000 -OutputFile G:\dir1\dir2\waka-waka.csv

Same applies to error file, specify it with -FailedFile param.

Any path can be passed in absolute (starts with drive letter) and relative format (starts with dot). 
Relative paths are relative to current directory.
Current directory can be obtained in powershell window by executing Get-Location (or just look at left part of command prompt).

By default, each failed request will be repeated once again. This can be configured by -RetryCount parameter.
Note, that request will be repeated immediately, so if there is some network issue or API limit restriction, it will fail again very probably.

In case of really weird situation that breaks script in the middle of process, no result file generated.
Instead, you will have a directory in the same path with same name. 
Inside there will be a bunch of little csv files, each representing result of one individual request.
To create final file from them, use -JustCollectResult parameter.
It will concatenate all the files in this directory and remove them afterwards.
Note that you have to specify input file and proxy even if they are not required for this operation.
Also -OutputFile should be passed in the same way it was before crash.
i.e: 
1) script was started with . .\whereventer.ps1 -InputFile .\links.txt -Proxy proxy -OutputFile .\out.csv
2) pc crashes
3) you now have directory .\out with some csv files
4) run . .\whereventer.ps1 -InputFile 'nomatter' -Proxy 'whocares' -OutputFile .\out.csv -JustCollectResults
5) out.csv is generated, out directory is removed, no additional requests were made.

If output file is already exists, it will be replaced with the new one. Script will prompt for confirmation.
If output file does not exists, but output directory is present (i.e. after pc crash) and you don't specify -JustCollectResults,
requests will be run again, so result csv can contain duplicated. 
If you don't want them, remove output directory manually or specify another output file.

This is all major highlight of script behaviour. Comments below are describing details of algorithm.
You can get description of any used command by executing Get-Help <command> (i.e. get-help export-csv).

If script isn't running at all, complaining something about execution policy, run Set-ExecutionPolicy Unrestricted -Scope CurrentUser
#>
Param(
	[Parameter(Mandatory=$true)][string]$InputFile, # file with links to request, one link per line
	[Parameter(Mandatory=$true)][string]$Proxy, # proxy address in format 'http(s)://address:port'. Do not forget http://!
	[string]$OutputFile = [System.IO.Path]::GetFullPath((Join-Path (Get-Location) "results.csv")), # resulting csv file
	[string]$FailedFile = [System.IO.Path]::GetFullPath((Join-Path (Get-Location) "failed.txt")), # here failed requests links will be written
    [string]$CompletedFile = [System.IO.Path]::GetFullPath((Join-Path (Get-Location) "completed.txt")), # here failed requests links will be written
	[int]$RetryCount = 1, # how many times retry request on any error
	[switch]$JustCollectResults) # do not request links, get result from previous crashed run

Set-StrictMode -Version "3.0"	
$ErrorActionPreference = "Stop"
Import-Module $PSScriptRoot\SplitPipeline

# here temp results will be stored, so create directory
$resultsDirectory = New-Item `
	-Name ([System.IO.Path]::GetFileNameWithoutExtension($OutputFile)) `
	-Path ([System.IO.Path]::GetDirectoryName($OutputFile)) `
	-ItemType Directory -Force

# this function get all files from results directory, treats them as csv and exports all into singe file.
# CSV schema is detected from the first one. So if others doesn't contain some property, it will be blank, 
# but if they have additional properties that first one doesn't have, csv will NOT contain them.
# So be sure to request only links that will return the same JSON schema responses in order not to lost data.
function CollectResults()
{
	Write-Host "Creaing result file"
	Get-ChildItem $resultsDirectory |% { Import-Csv $_.FullName | Export-Csv -Encoding UTF8 -NoTypeInformation -Path $OutputFile -Append -Force }
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

$stopwatch = [system.diagnostics.stopwatch]::StartNew() # start timer for statistics
$null | Out-File $FailedFile # clear errors file 

try
{
	Write-Host Output file is $OutputFile
	$links = Get-Content $InputFile # here is where file with links is being read entirely
    
    if (Test-Path $CompletedFile)
    {
        Write-Host "Found file with completed urls. Do you want to consider it and exclude these urls from input file? [Y|N]"
        Write-Host "Completed urls file will be deleted unless you type 'Y' symbol"
        $choice = Read-Host
        if ($choice -eq 'n' -or $choice -eq 'N')
        {
            Remove-Item $CompletedFile
        }
        else
        {
            $comletedLinks = Get-Content $CompletedFile
            $links = @($links |? { $comletedLinks -notcontains $_ })
            Move-Item $OutputFile "$resultsDirectory\$(New-Guid).csv" -ErrorAction SilentlyContinue
        }
    }    

    if (Test-Path $OutputFile)
    {
	    Write-Host 'Output file is already exists, it will be rewritten and old results will be deleted'
	    Write-Host 'Press Enter to continue or Ctrl+C to cancel'
	    Read-Host 
	    Remove-Item $OutputFile
	    Get-ChildItem $resultsDirectory | Remove-Item -Force
    }



	$data = @{
		proxy = $Proxy; 
		retryCount = $RetryCount;
		done = 0;
		failed = 0;
		total = $links.Count;
		currentDir = $PSScriptRoot;
	} # $data is just some object with settings and statistics

	# Split-Pipeline gives all links executes the -Script part in parallel. Default parallel degree is processor count.
	# You may want to increase it, so specify -Count parameter before -Variable (i.e Split-Pipeline -Count 10 -Variable ...)
	# Increasing parallelism degree does not guarantee an increase in speed. 
	# In some cases it can even slow down execution or lead to ban from API.
	$links | Split-Pipeline -Variable data, resultsDirectory, FailedFile, CompletedFile -Script `
	{process{

		# from here starts processing of one link 
		Import-Module "$($data.currentDir)\LockObject"
		. "$($data.currentDir)\ConvertTo-FlatObject.ps1"
		$uri = $_
		$attemptNumber = 0
		$success = $false
		$id = [System.Guid]::NewGuid() # result of request will be stored in file with this id

		while(-not $success -and $attemptNumber -le $data.retryCount) 
		{
			++$attemptNumber;
			try 
			{
				# this is the main logic.
				$response = Invoke-WebRequest -Uri $uri -Proxy $data.proxy -ProxyUseDefaultCredentials                
				$events = $response.AllElements | where { $_.class -eq "listing_item event" }
                $events |% {
                    $divs = $_.innerHTML -split "<div"
                    [PsCustomObject]@{
                        url = $uri;
                        thumb = (($divs[1] -split "src=`"")[-1] -split "`" ")[0];
                        title = (($divs[2] -split ">")[2] -split "</")[0];
                        datetime = (($divs[5] -split "datetime=`"")[1] -split "`"")[0];
                        location = (($divs[9] -split "location`">")[1] -split "</")[0];
                        femaleCount = (($divs[6] -split "count`">")[1] -split "</")[0];
                        maleCount = (($divs[7] -split "count`">")[1] -split "</")[0];
                     }
                } | Export-Csv -Encoding UTF8 -NoTypeInformation -Path "$resultsDirectory\$id.csv"
				$success = $true
			}
			catch
			{
				# we will fall here if any failure occured, no matter of origin: network problem or API reject.
				# in case of API failure there is no logging of detailed message, just something like "400 Bad Request" or "404 Not Found"
				Write-Host "Attempt $attemptNumber. $($_.Exception.Message) URI: $uri"
			}
		}

		# this part is for showing progress
		Lock-Object $data `
		{ 
			$done = ++$data.done
            Write-Host $uri processed. Success = $success
			if (!$success) 
			{
				++$data.failed
				$uri | Out-File $FailedFile -Append # here we write failed request link to errors file
			}
            else 
            {
                $uri | Out-File $CompletedFile -Append
            }
		}

		Write-Progress -Activity "Done $done of $($data.total)" -Status Processing -PercentComplete (100*$done/$data.total)			
	}}
}
finally
{
	# stop timer and show results
	$stopwatch.Stop()
	Write-Host Processed $($data.done - $data.failed) links of $($data.total)
	Write-Host Failed $data.failed "request(s)"
	Write-Host Total time: $($stopwatch.Elapsed)
	
	# finally collect all files into specified result file
	CollectResults
}
