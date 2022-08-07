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
	[ValidateRange(-1, 99999999)] [Int] $SeriesID = -1,
	[String] $Digits = '2',
	[Switch] $CleanName,
	[Switch] $HideProgress,
	[ValidateSet('libx264', 'libx265')] [String] $VideoCodec = 'libx265',
	[ValidatePattern('^(?i)(error|info)$')] [String] $LogLevel = 'error',
	[ValidateSet('yuv420p', 'yuv420p10le', '')] [String] $PixelFormat = 'yuv420p10le',
	[ValidateRange(-1.0, 1000.0)] [Float] $FrameRate = -1.0,
	[Switch] $ForcedSubsOnly,
	[Switch] $NoNormalize
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
Set-Variable -Name Replace -Value (Check-Replace $Replace)
Set-Variable -Name AudioLang -Value (Check-Lang $AudioLang)
Set-Variable -Name SubLang -Value (Check-Lang $SubLang)
Set-Variable -Name ScrapeLang -Value (Check-Lang $ScrapeLang)
Set-Variable -Name Digits -Value (Check-Digits $Digits)
Set-Variable -Name Threads -Value (Check-Threads $Threads)
Set-Variable -Name FrameRate -Value (Check-FrameRate $FrameRate)
Set-Variable -Name PixelFormat -Value (Check-PixelFormat $PixelFormat $VideoCodec)
Set-Variable -Name CRF -Value (Set-CRF $CRF $VideoCodec)

#Build A List Of Input Files And Display Them
$InputFormats = @('.m4v', '.vob', '.avi', '.flv', '.wmv', '.ts', '.m2ts', '.avs', '.mov', '.mkv', '.mp4', '.webm', '.ogm', '.mpg', '.mpeg')
$objInputList = Get-ChildItem -LiteralPath $InputPath -Recurse:(!$NoRecurse) -File | Where-Object {$InputFormats -contains $_.Extension}

If (!$objInputList) {
	Throw "No valid input files found."
}

Write-Host "`nInput File(s):"
($objInputList).Name

#Process Each File
$intFileCount = 1
$intTotalFileCount = $objInputList.Count
ForEach ($objFile In $objInputList) {
	Try {
		#Show Progress
		If (!$HideProgress -and !$ShowInfo) {
			$strProgress = "`nProcessing file $intFileCount of " + $intTotalFileCount
			$strLines = "`n" + ("=" * $strProgress.Length)
			Write-Host -ForegroundColor Cyan ($strLines + $strProgress + $strLines)
		}
		
		#Get Info From Input File
		$objFFInfo = .\bin\ffprobe.exe -v quiet -print_format json -show_entries format=duration,stream=codec_type -show_streams $objFile.FullName | ConvertFrom-Json
		
		#Define Info Object
		$objInfo = Construct-InfoObject
		
		#Define Info Object Values
		$objInfo.Input.FullName = $objFile.FullName
		$objInfo.Input.BaseName = $objFile.BaseName
		$objInfo.Input.Extension = $objFile.Extension
		$objInfo.Index.Video = Get-VideoIndex $objFFInfo $VideoIndex
		$objInfo.Index.Audio = Get-AudioIndex $objFFInfo $objInfo $AudioIndex $AudioLang $AudioTitle $NoAudio
		$objInfo.Index.Sub = Get-SubIndex $objFFInfo $objInfo $SubIndex $SubLang $SubTitle $Subs
		$objInfo.Input.Duration = Get-Duration $objFFInfo $objInfo
		$objInfo.Input.FrameCount = Get-FrameCount $objFFInfo $objInfo
		$objInfo.Input.FrameRate = Get-FrameRate $objFFInfo $objInfo $FrameRate $True
		$objInfo.Input.Resolution = Get-VideoRes $objFFInfo $objInfo
		$objInfo.Output.BaseNameClean = (Clean-Name $objInfo.Input.BaseName $Replace)
		$objInfo.Output.Random.BaseName = -join ((0x30..0x39) + ( 0x41..0x5A) + ( 0x61..0x7A) | Get-Random -Count 16 | % {[char]$_})
		$objInfo.Output.Extension = Get-OutputExtension $objInfo.Input.Extension $NoEncode
		$objInfo.Output.Random.FLAC = $objInfo.Output.Random.BaseName + '.flac'
		$objInfo.Output.Random.MP4 = $objInfo.Output.Random.BaseName + '.mp4'
		$objInfo.Output.Random.M4A = $objInfo.Output.Random.BaseName + '.m4a'
		$objInfo.Output.FrameRate = Get-FrameRate $objFFInfo $objInfo $FrameRate $False
		$objInfo.Scrape.ShowTitle = $ShowQuery
		$objInfo.Scrape.EpisodeTitle = $Null
		$objInfo.Scrape.Season = $SeasonQuery
		$objInfo.Scrape.Episode = $EpisodeQuery
		$objInfo.Output.FullName = Get-OutputPath $objInfo $OutputPath $Scrape $ScrapeLang $CleanName $EpisodeOffset $SeriesID $Digits
		
		#Show Useful Info
		Write-Host ("`nInput path: " + $objInfo.Input.FullName)
		
		#Show Extra Info And Continue Loop
		If ($ShowInfo) {
			Show-Info $objFFInfo

			$intFileCount++
			Continue
		}
		
		Write-Host ("Output path: " + $objInfo.Output.FullName)
		
		#Skip If We Cannot Overwrite
		If (($NoOverwrite) -and (Test-Path -LiteralPath $objInfo.Output.FullName)) {
			Write-Host "Output file exists. Skipping..."
			
			$intFileCount++
			Continue
		}
		
		#Only Rename File If Not Encoding
		If ($NoEncode) {
			New-Item -Path (Split-Path $objInfo.Output.FullName) -Type Directory -ErrorAction SilentlyContinue | Out-Null
			Move-Item -Force -LiteralPath $objInfo.Input.FullName -Destination $objInfo.Output.FullName

			$intFileCount++
			Continue
		}
		
		#Skip File If No Video Streams Found
		If ($objInfo.Index.Video -eq -1) {
			Write-Warning "No video stream(s) found, skipping."
			
			$intFileCount++
			Continue
		}
		
		#Show Duration
		Write-Host ("`nVideo Duration: " + $objInfo.Input.Duration.AsString + "`n")
		
		#Get Fonts If Needed
		If (($ObjInfo.Extension -eq '.mkv') -and ($ObjInfo.SubIndex -gt -1)) {
			Get-Fonts $objInfo
		}

		#Show Index Selection
		Write-Host ("Video Index: " + $objInfo.Index.Video)
		
		If ([Int]$objInfo.Index.Audio -gt -1) {
			Write-Host ("Audio Index: " + $objInfo.Index.Audio)
		}
		If ([Int]$objInfo.Index.Sub -gt -1) {
			Write-Host ("Subtitle Index: " + $objInfo.Index.Sub)
		}
		
		#Get Info For Filter String
		$objInfo.Filter.Crop = Set-Crop $objInfo $ForceCrop $NoCrop $MinRes
		$objInfo.Filter.Scale = Set-Scale $objInfo $Round $ForceRes $MinRes $MaxRes
		$objInfo.Filter.Subs = Set-Subs $objFFInfo $objInfo $ForceRes $Subs
		
		#Build Filter String And Show It
		$objInfo.Filter.Chain = Build-Filter $objInfo
		
		Write-Host ("`nFilter Chain: " + (Unescape-Filter $objInfo.Filter.Chain))
		
		#Show FFmpeg Version
		Write-Host ("`n" + (.\bin\ffmpeg -version | Select-Object -First 1).Trim())
		
		#Encode Video
		Write-Host -ForegroundColor Green "`nEncoding video"
		
		#If We Have A Valid Audio Index, Encode Audio And Video
		If ($objInfo.AudioIndex -ne -1) {
			.\bin\ffmpeg.exe -y -loglevel $LogLevel -stats -forced_subs_only ([Int]$ForcedSubsOnly.ToBool()) -i $objInfo.Input.FullName -r $objInfo.Output.FrameRate.AsString -an -sn -c:v $VideoCodec -preset:v $VideoPreset -x265-params log-level=error -pix_fmt $PixelFormat -crf:v $CRF -map [out] -filter_complex $objInfo.Filter.Chain -map_metadata -1 -map_chapters -1 $objInfo.Output.Random.MP4 `
			-map 0:$($objInfo.Index.Audio) -vn -sn -c:a flac -map_metadata -1 -map_chapters -1 -compression_level 0 -af aformat=sample_fmts=s16:channel_layouts=stereo:sample_rates=48000 $objInfo.Output.Random.FLAC
		}
		#Else Move The Video File To The Output File And Continue As There Is No Audio
		Else {
			New-Item -Path (Split-Path $objInfo.Output.FullName) -Type Directory -ErrorAction SilentlyContinue | Out-Null
			Move-Item -Force -LiteralPath $objInfo.Output.Random.MP4 -Destination $objInfo.Output.FullName -ErrorAction SilentlyContinue
			
			$intFileCount++
			Continue
		}

		#Encode Audio
		Write-Host -ForegroundColor Green "`nEncoding audio"
		.\bin\qaac64.exe $objInfo.Output.Random.FLAC -V($AudioQuality) -q 2 -o $objInfo.Output.Random.M4A
		
		#Apply Gain
		If (!$NoNormalize) {
			Write-Host -ForegroundColor Green "`nApplying ReplayGain"
			.\bin\aacgain.exe /r /k $objInfo.Output.Random.M4A
		}
		
		# Mux Video / Audio
		Write-Host -ForegroundColor Green "`nMuxing"
		New-Item -Path (Split-Path $objInfo.Output.FullName) -Type Directory -ErrorAction SilentlyContinue | Out-Null
		.\bin\mp4box.exe -add $objInfo.Output.Random.MP4 -add $objInfo.Output.Random.M4A -new $objInfo.Output.FullName
	}
	#Always Remove Temporary Files Before Finishing
	Finally {
		#Remove Fonts
		If ($objInfo.Output.Random.BaseName) {
			Remove-Item $objInfo.Output.Random.BaseName -ErrorAction SilentlyContinue -Force -Recurse
		}
		
		#Remove Temporary Files
		$objInfo.Output.Random.MP4, $objInfo.Output.Random.M4A, $objInfo.Output.Random.FLAC | Remove-Item -ErrorAction SilentlyContinue -Force -Recurse
	}
	
	#Increment Processed File Counter
	$intFileCount++
}

#Show Completed Message If Needed
If (!$HideProgress) {
	Write-Host "`nComplete."
}
