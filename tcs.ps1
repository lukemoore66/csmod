Param (
	[ValidateScript({ Test-Path -LiteralPath $_ })] [String] $InputListPath = ('{0}\tcsi.txt' -f $PSScriptRoot),
	[switch] $ExitIfEmpty
)

#exit if other instances are running
$strCommand = '*{0}*' -f $MyInvocation.MyCommand
$objOtherProcess = Get-Process | Where-Object { ($_.Name -eq 'pwsh') -and ($_.CommandLine -like $strCommand) -and ($_.Id -ne $PID) }
If ($objOtherProcess) { Stop-Process -Id $PID }

#set executable / module paths
$Script:strCsLibPath = '{0}\cslib.ps1' -f $PSScriptRoot
$Script:strCsPath = '{0}\cs.ps1' -f $PSScriptRoot

#set constant variables
$INIPathDefault = '{0}\ini\rss-default.ini' -f $PSScriptRoot
$OutputLogPath = '{0}\tcso.txt' -f $PSScriptRoot
$InputFormats = @('.m4v', '.vob', '.avi', '.flv', '.wmv', '.ts', '.m2ts', '.avs', '.mov', '.mkv', '.mp4', '.webm', '.ogm', '.mpg', '.mpeg')

#import functions
. $strCsLibPath

#make sure the default rule file exists
If (!(Test-Path -LiteralPath $INIPathDefault)) {
	Throw ("Default ini file '{0}' does not exist." -f $INIPathDefault)
}
	
$objTorrentList = [System.Collections.Generic.List[String]]::New()

#get all files within folders for torrent input list
$intLineCounter = 1
ForEach ($strLine in (Get-Content -LiteralPath $InputListPath)) {
	#skip if the line is blank
	If (-not $strLine.Trim()) {
		$intLineCounter++
		Continue
	}
	
	#seperate the torrent path from the ini
	$arrLine = $strLine.Split('|')
	
	#skip if torrent DNE
	If (-not (Test-Path -LiteralPath $arrLine[0])) {
		Write-Warning ("Input path: '{0}' at line {1} in '{2}' does not exist, Removing." -f $arrLine[0], $intLineCounter, $InputListPath)
		$intLineCounter++
		Continue
	}
	
	#if the torrent is a folder
	If ((Get-Item -LiteralPath $arrLine[0]).PSIsContainer) {
		#get the video files and add to the torrent list
		Get-ChildItem -LiteralPath $arrLine[0] -Recurse -File | Where-Object { $InputFormats -Contains $_.Extension } | ForEach-Object {
			$strLine = '{0}|{1}' -f $_.FullName, $arrLine[1]
			$objTorrentList.Add($strLine)
		}
		
		$intLineCounter++
		Continue
	}
	
	#otherwise, the torrent is a file
	$objTorrentList.Add($strLine)

	$intLineCounter++
}

#write new input list to input file
Set-Content -LiteralPath $InputListPath -Value $objTorrentList

#declare input list
$objInputList = [Ordered]@{}

#build input list
Get-Content -LiteralPath $InputListPath | ForEach-Object {
	$arrLine = $_.Split('|')
	$objInputList.Add($arrLine[0], (Get-INIPath $arrLine[0] $arrLine[1]))
}

#show an error if the input list is empty
If ($objInputList.Count -lt 1) {
	Write-Warning ("Input list: '{0}' is empty. Exiting.`n" -f $InputListPath)
	
	If ($ExitIfEmpty) {
		Start-Sleep 3
		Stop-Process -Id $PID
	}
}

#show the input list
"Input Files:"
$objInputList.Keys
''

#loop through input list
$intFileCount = 1
$intTotalFileCount = 
$objInputList.GetEnumerator() | ForEach-Object {
	#show progress
	$strProgress = "`nProcessing File {0} of {1}" -f $intFileCount, $objInputList.Count
	$strLines = "`n" + ("=" * $strProgress.Length)
	Write-Host -ForegroundColor Cyan ($strLines + $strProgress + $strLines)
	
	#run csmod
	& $strCsPath -InputPath $_.Key -INIPath $_.Value
	
	#assign current input list line
	$strInputListLine = $_.Key + '|' + (Get-Item -LiteralPath $_.Value).BaseName
	
	#remove current input line from input list
	Set-Content -LiteralPath $InputListPath -Value (Get-Content -LiteralPath $InputListPath | Where-Object { $_ -iNotMatch [Regex]::Escape($strInputListLine) })
	
	#write current input line to the output log
	Add-Content -LiteralPath $OutputLogPath -Value ((Get-Date).ToString() + '|' + $strInputListLine)
	
	#write an empty line
	If ($intTotalFileCount -lt $objInputList.Count) {
		''
	}
	
	$intFileCount++
}

If ($objInputList.Count -gt 0) {
	Write-Host "`nAll Torrents Processed."
}