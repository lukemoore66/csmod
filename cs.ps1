Param (
	[Parameter(Mandatory = $True)] [ValidateScript({Test-Path -LiteralPath $_})] [String] $InputPath,
	[ValidateScript({Test-Path -LiteralPath $_ -PathType Container})] [String] $OutputPath = $PSScriptRoot,
	[ValidateScript({Test-Path -LiteralPath $_})] [String] $INIPath,
	[Switch] $NoRecurse,
	[Switch] $Scrape,
	[Switch] $Subs,
	[Switch] $ShowInfo,
	[ValidateRange(-1, 51)] [Int] $CRF = -1,
	[String] $AudioLang,
	[String] $SubLang,
	[String] $ScrapeLang,
	[ValidateRange(-1, 99)] [Int] $AudioIndex = -1,
	[ValidateRange(-1, 99)] [Int] $VideoIndex = -1,
	[ValidateRange(-1, 99)] [Int] $SubIndex = -1,
	[String] $AudioTitle,
	[String] $SubTitle,
	[Switch] $NoEncode,
	[Switch] $NoAudio,
	[Switch] $NoOverwrite,
	[ValidateRange(0, 127)] [Int] $AudioQuality = 90,
	[String] $VideoPreset = 'medium',
	[ValidatePattern('(^\d{1,4}:\d{1,4}:\d{1,4}:\d{1,4}$)|(^$)')] [String] $ForceCrop,
	[ValidatePattern('(^\d{1,4}x\d{1,4}$)|(^$)')] [String] $ForceRes,
	[ValidatePattern('^\d{1,4}x\d{1,4}$')] [String] $MinRes = '64x64',
	[ValidatePattern('^\d{1,4}x\d{1,4}$')] [String] $MaxRes = '1920x1080',
	[String[]] $Replace = @(),
	[ValidateRange(0, 128)] [Int] $Round = 16,
	[Switch] $NoCrop,
	[String] $ShowQuery,
	[ValidateRange(-1, 99)] [Int] $SeasonQuery = -1,
	[ValidateRange(-1, 999)] [Int] $EpisodeQuery = -1,
	[ValidateRange(-999, 999)] [Int] $EpisodeOffset = 0,
	[ValidateRange(0, 99999999)] [Int] $SeriesID = -1,
	[String] $Digits = '2',
	[Switch] $CleanName,
	[Parameter(DontShow = $True)] [Switch] $HideProgress,
	[ValidateSet('libx264', 'libx265')] [String] $VideoCodec = 'libx265',
	[ValidatePattern('^(?i)(error|info)$')] [String] $LogLevel = 'error',
	[ValidateSet('yuv420p', 'yuv420p10le')] [String] $PixelFormat = 'yuv420p10le',
	[ValidateRange(-1.0, 1000.0)] [Float] $FrameRate = -1.0
)

#Make We Are Sure Running From Script Directory
If ((Get-Location).Path -ne $PSScriptRoot) {
	Throw ("This script can only be run from it's own directory: '" + $PSScriptRoot + "'")
}

#Import Functions
. .\cslib.ps1

#Import INI Settings (Overwrites Command Line Parameters)
Process-INI $INIPath ((Get-Command -Name $MyInvocation.InvocationName).Parameters).Keys

#Check Parameters
Set-Variable -Name InputPath -Value (Check-Path $InputPath)
Set-Variable -Name OutputPath -Value (Check-Path $OutputPath)
Set-Variable -Name Subs -Value (Check-Subs $Subs $SubIndex $SubTitle $SubLang)
Set-Variable -Name Scrape -Value (Check-Scrape $Scrape $ShowQuery $SeasonQuery $EpisodeQuery $ScrapeLang $SeriesID $EpisodeOffset)
Set-Variable -Name VideoPreset -Value  (Check-VideoPreset $VideoPreset)
Set-Variable -Name AudioLang -Value (Check-Lang $AudioLang)
Set-Variable -Name SubLang -Value (Check-Lang $SubLang)
Set-Variable -Name ScrapeLang -Value (Check-Lang $ScrapeLang)
Set-Variable -Name Digits -Value (Check-Digits $Digits)
Set-Variable -Name Threads -Value (Check-Threads $Threads)
Set-Variable -Name FrameRate -Value (Check-FrameRate $FrameRate)

#If No CRF Is Set, Automatically Set CRF Value, Depending On Chosen Video Codec
If ($CRF -eq -1) {
	Set-Variable -Name CRF -Value (Set-CRF $CRF $VideoCodec)
}

#Build A List Of Input Files And Display Them
$InputFormats = @('.m4v', '.vob', '.avi', '.flv', '.wmv', '.ts', '.m2ts', '.avs', '.mov', '.mkv', '.mp4', '.webm', '.ogm', '.mpg', '.mpeg')
$objInputList = Get-ChildItem -LiteralPath $InputPath -Recurse:(!$NoRecurse) -File | Where-Object {$InputFormats -contains $_.Extension}
If (!$objInputList) {
	Throw "No valid input files found."
}

Write-Host "Input File(s):"
($objInputList).Name

#Process Each File
$intFileCount = 1
$intTotalFileCount = $objInputList.Count
ForEach ($objFile In $objInputList) {
	Try {
		#Show Progress
		If (!$HideProgress) {
			$strProgress = "`nProcessing file $intFileCount of " + $intTotalFileCount
			$strLines = "`n" + ("=" * $strProgress.Length)
			Write-Host -ForegroundColor Cyan ($strLines + $strProgress + $strLines)
		}
		
		#Get Info From Input File
		$objInfo = .\bin\ffprobe.exe -v quiet -print_format json -show_entries format=duration,stream=codec_type -show_streams $objFile.FullName | ConvertFrom-Json
		
		#Get Additional Info About The Input File
		$objInfo | Add-Member -NotePropertyName 'DurationSexagesimal' -NotePropertyValue (Get-Sexagesimal $objInfo.format.duration) | Out-Null
		$objInfo | Add-Member -NotePropertyName 'BaseName' -NotePropertyValue $objFile.BaseName | Out-Null
		$objInfo | Add-Member -NotePropertyName 'FullName' -NotePropertyValue $objFile.FullName | Out-Null
		$objInfo | Add-Member -NotePropertyName 'Extension' -NotePropertyValue $objFile.Extension | Out-Null
		$objInfo | Add-Member -NotePropertyName 'BaseNameCleaned' -NotePropertyValue (Clean-Name $objInfo.BaseName $Replace)
		$objInfo | Add-Member -NotePropertyName 'ShowTitle' -NotePropertyValue $ShowQuery
		$objInfo | Add-Member -NotePropertyName 'SeasonNumber' -NotePropertyValue $SeasonQuery
		$objInfo | Add-Member -NotePropertyName 'EpisodeNumber' -NotePropertyValue $EpisodeQuery
		$objInfo | Add-Member -NotePropertyName 'EpisodeTitle' -NotePropertyValue $null
		$objInfo | Add-Member -NotePropertyName 'FullNameOutput' -NotePropertyValue (Get-FullNameOutput $objInfo $OutputPath $Scrape $ScrapeLang $CleanName $EpisodeOffset $SeriesID $Digits) | Out-Null
		
		#Show Useful Info
		Write-Host ("`nInput path: " + $objInfo.FullName)
		
		#Show Extra Info And Continue
		If ($ShowInfo) {
			$objInfo.streams | Format-Table -AutoSize -Property index, codec_type, codec_name, tags
			
			$intFileCount++
			Continue
		}
		
		Write-Host ("Output path: " + $objInfo.FullNameOutput)
		
		#Skip If We Cannot Overwrite
		If (Test-Path -LiteralPath $objInfo.FullNameOutput) {
			Write-Host "Output file exists. Skipping..."
			
			$intFileCount++
			Continue
		}
		
		#Only Rename File If Not Encoding
		If ($NoEncode) {
			New-Item -Path (Split-Path $objInfo.FullNameOutput) -Type Directory -ErrorAction SilentlyContinue | Out-Null
			Move-Item -Force -LiteralPath $objInfo.FullName -Destination $objInfo.FullNameOutput #-ErrorAction SilentlyContinue
			
			$intFileCount++
			Continue
		}
		
		#Show Duration
		Write-Host ("`nEstimated Duration: " + $objInfo.DurationSexagesimal + "`n")
		
		#Set Up A Random Name For Temporary Files
		$objInfo | Add-Member -NotePropertyName 'RandomBaseName' -NotePropertyValue (-join ((0x30..0x39) + ( 0x41..0x5A) + ( 0x61..0x7A) | Get-Random -Count 16 | % {[char]$_})) | Out-Null
		$objInfo | Add-Member -NotePropertyName 'RandomBaseNameFLAC' -NotePropertyValue ($objInfo.RandomBaseName + '.flac') | Out-Null
		$objInfo | Add-Member -NotePropertyName 'RandomBaseNameMP4' -NotePropertyValue ($objInfo.RandomBaseName + '.mp4') | Out-Null
		$objInfo | Add-Member -NotePropertyName 'RandomBaseNameM4A' -NotePropertyValue ($objInfo.RandomBaseName + '.m4a') | Out-Null
		
		#Set Up Index Selection
		$objInfo | Add-Member -NotePropertyName 'VideoIndex' -NotePropertyValue (Get-VideoIndex $objInfo $VideoIndex) | Out-Null
		
		#Get Framerate From Source Video If Needed
		If ($FrameRate -eq -1.0) {
			[string]$FrameRate = Get-FrameRate $objInfo $FrameRate
		}
		
		#Skip File If No Video Streams Found
		If ($objInfo.VideoIndex -eq -1) {
			Write-Warning "No video stream(s) found, skipping."
			
			$intFileCount++
			Continue
		}
		
		$objInfo | Add-Member -NotePropertyName 'AudioIndex' -NotePropertyValue (Get-AudioIndex $objInfo $AudioIndex $AudioLang $AudioTitle $NoAudio) | Out-Null
		$objInfo | Add-Member -NotePropertyName 'SubIndex' -NotePropertyValue (Get-SubIndex $objInfo $SubIndex $SubLang $SubTitle $Subs) | Out-Null
		
		#Get Fonts If Needed
		If (($ObjInfo.Extension -eq '.mkv') -and ($ObjInfo.SubIndex -gt -1)) {
			Get-Fonts $objInfo
		}

		#Show Index Selection
		Write-Host ("Video Index: " + $objInfo.VideoIndex)
		
		If ([Int]$objInfo.AudioIndex -gt -1) {
			Write-Host ("Audio Index: " + $objInfo.AudioIndex)
		}
		If ([Int]$objInfo.SubIndex -gt -1) {
			Write-Host ("Subtitle Index: " + $objInfo.SubIndex)
		}
		
		#Get Info For Filter String
		$objInfo | Add-Member -NotePropertyName 'Crop' -NotePropertyValue (Set-Crop $objInfo $ForceCrop $NoCrop $MinRes) | Out-Null
		$objInfo | Add-Member -NotePropertyName 'Scale' -NotePropertyValue (Set-Scale $objInfo $Round $ForceRes $MinRes $MaxRes) | Out-Null
		$objInfo | Add-Member -NotePropertyName 'Subs' -NotePropertyValue (Set-Subs $objInfo $ForceRes $Subs) | Out-Null
		
		#Build Filter String And Show It
		$strVideoFilter = Build-Filter $objInfo
		
		Write-Host ("`nFilter Chain: " + (Unescape-Filter $strVideoFilter))
		
		#Show FFmpeg Version
		Write-Host ("`n" + (.\bin\ffmpeg -version | Select-Object -First 1).Trim())
		
		Write-Host -ForegroundColor Green "`nEncoding video"
		.\bin\ffmpeg.exe -y -loglevel $LogLevel -stats -i $objInfo.FullName -r $FrameRate -an -sn -c:v $VideoCodec -preset:v $VideoPreset -x265-params log-level=error -pix_fmt $PixelFormat -crf:v $CRF -map [out] -filter_complex $strVideoFilter -map_metadata -1 -map_chapters -1 $objInfo.RandomBaseNameMP4

		#Move The Video File To The Output File And Continue If There Is No Audio
		If ($objInfo.AudioIndex -eq -1) {
			New-Item -Path (Split-Path $objInfo.FullNameOutput) -Type Directory -ErrorAction SilentlyContinue | Out-Null
			Move-Item -Force -LiteralPath $objInfo.RandomBaseNameMP4 -Destination $objInfo.FullNameOutput -ErrorAction SilentlyContinue
			
			$intFileCount++
			Continue
		}
		
		#Demux Audio
		Write-Host -ForegroundColor Green "`nDecoding audio"

		#Get Duration Of Temporary Video File
		$strEncDuration = .\bin\ffprobe.exe -v quiet -print_format default=noprint_wrappers=1:nokey=1 -show_entries format=duration $objInfo.RandomBaseNameMP4
		
		#Decode Audio
		.\bin\ffmpeg.exe -y -loglevel $LogLevel -stats -i $objInfo.FullName -map 0:$($objInfo.AudioIndex) -t $strEncDuration -vn -sn -map_metadata -1 -map_chapters -1 -c:a flac -compression_level 0 -af aformat=sample_fmts=s16:channel_layouts=stereo:sample_rates=48000 $objInfo.RandomBaseNameFLAC
		
		#Encode Audio
		Write-Host -ForegroundColor Green "`nEncoding audio"
		.\bin\qaac64.exe $objInfo.RandomBaseNameFLAC -V($AudioQuality) -q 2 -o $objInfo.RandomBaseNameM4A
		
		#Apply Gain
		Write-Host -ForegroundColor Green "`nApplying ReplayGain"
		.\bin\aacgain.exe /r /k $objInfo.RandomBaseNameM4A
		
		# Mux Video / Audio
		Write-Host -ForegroundColor Green "`nMuxing"
		New-Item -Path (Split-Path $objInfo.FullNameOutput) -Type Directory -ErrorAction SilentlyContinue | Out-Null
		.\bin\mp4box.exe -add $objInfo.RandomBaseNameMP4 -add $objInfo.RandomBaseNameM4A -new $objInfo.FullNameOutput
	}
	#Always Remove Temporary Files Before Finishing
	Finally {
		#Remove Fonts
		If ($objInfo.RandomBaseName) {
			Remove-Item $objInfo.RandomBaseName -ErrorAction SilentlyContinue -Force -Recurse
		}
		
		#Remove Temporary Files
		$objInfo.RandomBaseNameMP4, $objInfo.RandomBaseNameM4A, $objInfo.RandomBaseNameFLAC | Remove-Item -ErrorAction SilentlyContinue -Force -Recurse
	}
	
	#Increment Processed File Counter
	$intFileCount++
}

#Show Completed Message If Needed
If (!$HideProgress) {
	Write-Host "`nComplete."
}