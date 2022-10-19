Param (
	[ValidateScript({Test-Path -LiteralPath $_})] [String] $InputListPath = ($PSScriptRoot + '\tcsi.txt'),
	[switch] $ExitIfEmpty
)

#exit if other instances are running
$strCommand = '*{0}*' -f $MyInvocation.MyCommand
$objOtherProcess = Get-Process | Where-Object {($_.Name -eq 'pwsh') -and ($_.CommandLine -like $strCommand) -and ($_.Id -ne $PID)}
If ($objOtherProcess) {Stop-Process -Id $PID}

#set executable / module paths
$Script:strCsLibPath = '{0}\cslib.ps1' -f $PSScriptRoot
$Script:strCsPath = '{0}\cs.ps1' -f $PSScriptRoot

#Set Constant Variables
$INIPathDefault = '{0}\ini\rss-default.ini' -f $PSScriptRoot
$OutputLogPath = '{0}\tcso.txt' -f $PSScriptRoot
$InputFormats = @('.m4v', '.vob', '.avi', '.flv', '.wmv', '.ts', '.m2ts', '.avs', '.mov', '.mkv', '.mp4', '.webm', '.ogm', '.mpg', '.mpeg')

#Import Functions
. $strCsLibPath

#Make Sure The Default Rule File Exists
If (!(Test-Path -LiteralPath $INIPathDefault)) {
	Throw ("Default ini file '{0}' does not exist." -f $INIPathDefault)
}
	
$objInputList = [System.Collections.Generic.List[String]]::New()

#Get All Files Within Folders For Input List
Get-Content -LiteralPath $InputListPath | ForEach-Object {
	If ($_.Trim()) {
		$arrLine = $_.Split('|')
		#First Check If File Exists
		If (Test-Path -LiteralPath $arrLine[0]) {
			If ((Get-Item -LiteralPath $arrLine[0]).PSIsContainer) {
				Get-ChildItem -LiteralPath $arrLine[0] -Recurse -File | Where-Object {$InputFormats -Contains $_.Extension} | ForEach-Object {
					$strLine = '{0}|{1}' -f $_.FullName, $arrLine[1]
					$objInputList.Add($strLine)
				}
			}
			Else {
				$strLine = '{0}|{1}' -f $arrLine[0], $arrLine[1]
				$objInputList.Add($strLine)
			}
		}
		#Otherwise The Input File Does Not Exist
		Else {
			Write-Warning ("Input path: '{0}' at line {1} in '{2}' does not exist, skipping." -f $arrLine[0], $intLineCounter, $InputListPath)
		}
	}
}

#Write New Input List To Input File
$objInputList | Set-Content -LiteralPath $InputListPath -Force

#Declare Input List
$objInputList = [Ordered]@{}

#Get Input List
Get-Content -LiteralPath $InputListPath | % {
	If ($_.Trim()) {
		$arrLine = $_.Split('|')
		#First Check If File Exists
		If (Test-Path -LiteralPath $arrLine[0]) {
			$objInputList.Add($arrLine[0], (Get-INIPath $arrLine[0] $arrLine[1]))
		}
		#Otherwise The Input File Does Not Exist
		Else {
			Write-Warning ("Input file: '{0}' at line {1} in '{2}' does not exist, skipping." -f $arrLine[0], $intLineCounter, $InputListPath)
		}
	}
}

#Loop Through Input List
$intFileCount = 1
$intTotalFileCount = $objInputList.Count

#Show An Error If The Input List Is Empty
If ($objInputList.Count -lt 1) {
	Write-Warning ("Input list: '" + $InputListPath + "' is empty.`n")
	
	If ($ExitIfEmpty) {
		Start-Sleep 3
		Stop-Process -Id $PID
	}
}

$objInputList.GetEnumerator() | % {
	#Show Progress
	$strProgress = "`nProcessing File $intFileCount of " + $intTotalFileCount
	$strLines = "`n" + ("=" * $strProgress.Length)
	Write-Host -ForegroundColor Cyan ($strLines.SubString(1, $strLines.Length - 1) + $strProgress + $strLines)
	
	#Run csmod
	& $strCsPath -InputPath $_.Key -INIPath $_.Value
	
	#Assign Current Input List Line
	$strInputListLine = $_.Key + '|' + (Get-Item -LiteralPath $_.Value).BaseName
	
	#Remove Current Input Line From Input List
	Set-Content -LiteralPath $InputListPath -Value (Get-Content -LiteralPath $InputListPath | Where-Object {$_ -iNotMatch [Regex]::Escape($strInputListLine)})
	
	#Write Current Input Line To The Output Log
	Add-Content -LiteralPath $OutputLogPath -Value ((Get-Date).ToString() + '|' + $strInputListLine)
	
	#Write An Empty Line
	If ($intTotalFileCount -lt $objInputList.Count) {''}
	
	$intFileCount++
}

If ($objInputList.Count -gt 0)  {
	Write-Host "`nAll Torrents Processed."
}