Param (
	[ValidateScript({Test-Path -LiteralPath $_})] [String] $InputListPath = ($PSScriptRoot + '\tcsi.txt')
)

#Make Sure We Are Running From Current Directory
If ((Get-Location).Path -ne $PSScriptRoot) {
	Throw ("This script can only be run from it's own directory: " + $PSScriptRoot)
}

. .\cslib.ps1

#Set Constant Variables
$INIPathDefault = $PSScriptRoot + '\ini\rss-default.ini'
$OutputLogPath = $PSScriptRoot + '\tcso.txt'

#Make Sure The Default Rule File Exists
If (!(Test-Path -LiteralPath $INIPathDefault)) {
		Throw ("Default ini file '" + $INIPathDefault + "' does not exist.")
	}

#Define Input List
$objInputList = [Ordered]@{}

#Get Input List
Get-Content -LiteralPath $InputListPath | % {
	If ($_ -and $_.Trim()) {
		$arrLine = $_.Split('|')
		#First Check If File Exists
		If (Test-Path -LiteralPath $arrLine[0]) {
			$objInputList.Add($arrLine[0], (Get-INIPath $arrLine[0] $arrLine[1]))
		}
		#Otherwise The Input File Does Not Exist
		Else {
			Write-Warning ("Input file: '" + $arrLine[0] + "' at line " + $intLineCounter + " in " + $InputListPath + " is invalid, skipping.")
		}
	}
}

#Loop Through Input List
$intFileCount = 1
$intTotalFileCount = $objInputList.Count

#Show An Error If The Input List Is Empty
If ($objInputList.Count -lt 1) {
	Throw ("Input list: '" + $InputListPath + "' is empty.")
}

$objInputList.GetEnumerator() | % {
	#Show Progress
	$strProgress = "`nProcessing torrent $intFileCount of " + $intTotalFileCount
	$strLines = "`n" + ("=" * $strProgress.Length)
	Write-Host -ForegroundColor Cyan ($strLines + $strProgress + $strLines + "`n")
	
	#Run csmod
	.\cs.ps1 -InputPath $_.Key -INIPath $_.Value -HideProgress:$True
	
	#Assign Current Input List Line
	$strInputListLine = $_.Key + '|' + (Get-Item -LiteralPath $_.Value).BaseName
	
	#Remove Current Input Line From Input List
	Set-Content -LiteralPath $InputListPath -Value (Get-Content -LiteralPath $InputListPath | Where-Object {$_ -iNotMatch [Regex]::Escape($strInputListLine)})
	
	#Write Current Input Line To The Output Log
	Add-Content -LiteralPath $OutputLogPath -Value ((Get-Date).ToString() + '|' + $strInputListLine)
	
	$intFileCount++
}

Write-Host "`nComplete."