Param (
	[Parameter(Mandatory = $True)] [ValidateScript({ Test-Path -LiteralPath $_ })] [string] $InputPath,
	[ValidateScript({ Test-Path -LiteralPath $_ -PathType Container })] [string] $OutputPath = $PSScriptRoot,
	[ValidateScript({ Test-Path -LiteralPath $_ })] [string] $INIPath,
	[Switch] $NoRecurse,
	[Switch] $Scrape,
	[Switch] $Subs,
	[Switch] $ShowInfo,
	[ValidateRange(-1, 51)] [int] $CRF = -1,
	[string] $AudioLang,
	[string] $SubLang,
	[string] $ScrapeLang,
	[ValidateRange(-1, 99)] [int] $AudioIndex = -1,
	[ValidateRange(-1, 99)] [int] $VideoIndex = -1,
	[ValidateRange(-1, 99)] [int] $SubIndex = -1,
	[string] $AudioTitle,
	[string] $SubTitle,
	[Switch] $NoEncode,
	[Switch] $NoAudio,
	[Switch] $NoOverwrite,
	[ValidateRange(0, 127)] [int] $AudioQuality = 90,
	[string] $VideoPreset = 'medium',
	[ValidatePattern('(^\d{1,4}:\d{1,4}:\d{1,4}:\d{1,4}$)|(^$)')] [string] $ForceCrop,
	[ValidatePattern('(^\d{1,4}x\d{1,4}$)|(^$)')] [string] $ForceRes,
	[ValidatePattern('^\d{1,4}x\d{1,4}$')] [string] $MinRes = '64x64',
	[ValidatePattern('^\d{1,4}x\d{1,4}$')] [string] $MaxRes = '1920x1080',
	[string[]] $Replace,
	[ValidateRange(2, 16)] [int] $Round = 8,
	[Switch] $NoCrop,
	[Switch] $NoScale,
	[string] $ShowQuery,
	[ValidateRange(-1, 99)] [int] $SeasonQuery = -1,
	[ValidateRange(-1, 999)] [int] $EpisodeQuery = -1,
	[ValidateRange(-1, [int]::MaxValue)] [int] $SeriesID = -1,
	[Switch] $CleanName,
	[Switch] $HideProgress,
	[ValidateSet('libx264', 'libx265')] [string] $VideoCodec = 'libx265',
	[ValidatePattern('^(?i)(error|info|debug)$')] [string] $LogLevel = 'error',
	[ValidateSet('auto', 'yuv420p', 'yuv420p10le')] [string] $PixelFormat = 'auto',
	[string] $FrameRateIn = 'auto',
	[string] $FrameRateOut = 'auto',
	[Switch] $ForcedSubsOnly,
	[Switch] $NoNormalize,
	[ValidateSet(0, 1, 2)] [int] $Deinterlace = 0,
	[Switch] $Replicate,
	[ValidateRange(-999, 999)] [int] $EpisodeOffset = 0
)

#ensure we have the correct powershell version
$intPSMinimumVersion = 7
If ($PSVersionTable.PSVersion.Major -lt $intPSMinimumVersion) {
	Throw ("This script requires PowerShell v$intPSMinimumVersion and up to run.")
}

#set executable / module paths
$Script:strCsLibPath = '{0}\cslib.ps1' -f $PSScriptRoot
$Script:strFFmpegPath = '{0}\bin\ffmpeg.exe' -f $PSScriptRoot
$Script:strFFprobePath = '{0}\bin\ffprobe.exe' -f $PSScriptRoot
$Script:strQaacPath = '{0}\bin\qaac64.exe' -f $PSScriptRoot
$Script:strAACGainPath = '{0}\bin\aacgain.exe' -f $PSScriptRoot
$Script:strMP4BoxPath = '{0}\bin\mp4box.exe' -f $PSScriptRoot

#dot source functions and classes
. $strCsLibPath

#import ini parameters (overwrites command line parameters)
$strInvocationName = '{0}\{1}' -f $PSScriptRoot , $MyInvocation.MyCommand
$objParameters = ((Get-Command -Name $strInvocationName).Parameters).Keys

Get-INI $INIPath $objParameters

#check parameters
Set-Variable -Name InputPath -Value (Set-Path $InputPath)
Set-Variable -Name OutputPath -Value (Set-Path $OutputPath)
Set-Variable -Name Subs -Value (Set-SubsInit $Subs $SubIndex $SubTitle $SubLang)
Set-Variable -Name Scrape -Value (Set-Scrape $Scrape $ShowQuery $ScrapeLang $SeasonQuery $EpisodeQuery $SeriesID)
Set-Variable -Name VideoPreset -Value  (Set-VideoPreset $VideoPreset)
Set-Variable -Name Replace -Value (Set-Replace $Replace)
Set-Variable -Name AudioLang -Value (Set-Lang $AudioLang)
Set-Variable -Name SubLang -Value (Set-Lang $SubLang)
Set-Variable -Name ScrapeLang -Value (Set-Lang $ScrapeLang)
Set-Variable -Name FrameRateIn -Value (Set-FrameRate $FrameRateIn $True)
Set-Variable -Name FrameRateOut -Value (Set-FrameRate $FrameRateOut $False)
Set-Variable -Name CRF -Value (Set-CRF $CRF $VideoCodec)

#build a list of input files and display them
$InputFormats = @('.m4v', '.vob', '.avi', '.flv', '.wmv', '.ts', '.m2ts', '.avs', '.mov', '.mkv', '.mp4', '.webm', '.ogm', '.mpg', '.mpeg')
$objInputList = Get-ChildItem -LiteralPath $InputPath -Recurse:(-not $NoRecurse) -File | Where-Object { $InputFormats -Contains $_.Extension }

If (-not $objInputList) {
	Throw "No valid input files found."
}

Write-Host "`nInput File(s):"
($objInputList).Name

#process each file
$intFileCount = 1
$intTotalFileCount = $objInputList.Count
ForEach ($objFile In $objInputList) {
	Try {
		###HACK TO ALLOW LEGACY COMMAND PARSING FOR NOW###
		$PSNativeCommandArgumentPassingOrig = $PSNativeCommandArgumentPassing
		$PSNativeCommandArgumentPassing = 'Legacy'
		
		#show progress
		If ((-not $HideProgress) -and (-not $ShowInfo)) {
			$strProgress = "`nProcessing file $intFileCount of " + $intTotalFileCount
			$strLines = "`n" + ("=" * $strProgress.Length)
			Write-Host -ForegroundColor Cyan ($strLines + $strProgress + $strLines)
		}

		#show useful info
		Write-Host ("`nInput path: " + $objFile.FullName)

		#get info from input file
		$objFFInfo = & $strFFprobePath -v quiet -print_format json -show_entries format=duration,stream=codec_type -show_streams $objFile.FullName | ConvertFrom-Json

		#show extra info and continue loop
		If ($ShowInfo) {
			Show-Info $objFFInfo

			Continue
		}

		#construct input file object
		$objInputFile = [InputFile]::new()
		$objInputFile.FullName = $objFile.FullName
		$objInputFile.BaseName = $objFile.BaseName
		$objInputFile.Extension = $objFile.Extension
		$objInputFile.Directory = $objFile.Directory.ToString()

		#get video index
		$objInputFile.Index.Vid = Get-VideoIndex $objFFInfo $VideoIndex
		
		#create temporary file info object, this generate random names
		$objTempFile = [TempFile]::new($objInputFile.FullName)

		#skip file if no video streams found
		If ($objInputFile.Index.Vid -eq -1) {
			Write-Warning "No video stream(s) found, skipping."

			$intFileCount++
			Continue
		}

		#construct an output file object
		$objOutputFile = [OutputFile]::new()
		$objOutputFile.BaseName = $objInputFile.BaseName
		$objOutputFile.BaseNameClean = Format-BaseName $objOutputFile.BaseName $Replace
		$objOutputFile.Extension = Get-OutputExtension $objInputFile.Extension $NoEncode

		#if we are scraping,
		If ($Scrape) {
			#construct a scrape object
			$objScrape = [Scrape]::new($objOutputFile.BaseNameClean, $SeriesID, $ShowQuery, $SeasonQuery, $EpisodeQuery, $ScrapeLang, $EpisodeOffset)

			#if the scrape was a success, make the output path using scraped data
			If ($objScrape.Success) {
				$objOutputFile.Directory = '{0}\{1}\Season {2:d2}' -f $OutputPath, $objScrape.Series.Name, $objScrape.Season
				$arrOutputFile = @($objScrape.Series.Name, $objScrape.Season, $objScrape.Episode, $objScrape.Title)
				$objOutputFile.BaseName = '{0} S{1:d2}E{2:d2} - {3}' -f $arrOutputFile
			}
		}

		#if scraping was not successful
		If (-not $objScrape.Success) {
			#if we elected to clean the basename
			If ($CleanName) {
				$objOutputFile.BaseName = $objOutputFile.BaseNameClean
			}

			#replicate the input folder structure if needed
			If (($Replicate) -and ((Get-Item $InputPath) -is [System.IO.DirectoryInfo])) {
				$objOutputFile.Directory = $objInputFile.Directory.Replace($InputPath, $OutputPath)
			}
			#otherwise, just set the output path as normal
			Else {
				$objOutputFile.Directory = $OutputPath
			}
		}

		$objOutputFile.FullName = '{0}\{1}{2}' -f $objOutputFile.Directory, $objOutputFile.BaseName, $objOutputFile.Extension

		Write-Host ("Output path: " + $objOutputFile.FullName)

		#skip if we cannot overwrite
		If (($NoOverwrite) -and (Test-Path -LiteralPath $objOutputFile.FullName)) {
			Write-Host "Output file exists. Skipping..."

			Continue
		}

		#only rename file if not encoding
		If ($NoEncode) {
			New-Item -Path $objOutputFile.Directory -Type Directory -ErrorAction SilentlyContinue | Out-Null
			Move-Item -Force -LiteralPath $objInputFile.FullName -Destination $objOutputFile.FullName

			Continue
		}

		#fill input properties
		$objInputFile.Duration = Get-VideoDuration $objFFInfo $objInputFile
		$objInputFile.FrameRate = Get-InputFrameRate $objFFInfo $objInputFile $FrameRateIn
		$objInputFile.Resolution = Get-VideoResolution $objFFInfo $objInputFile
		$objInputFile.PixelFormat = Get-PixelFormat $objFFInfo $objInputFile

		#get the audio and subtitle index for the input file
		$objInputFile.Index.Aud = Get-AudioIndex $objFFInfo $AudioIndex $AudioLang $AudioTitle $NoAudio
		$objInputFile.Index.Sub = Get-SubIndex $objFFInfo $SubIndex $SubLang $SubTitle $Subs

		#fill output properties
		$objOutputFile.FrameRate = Set-OutputFrameRate $objInputFile $FrameRateOut $Deinterlace
		$objOutputFile.PixelFormat = Set-OutputPixelFormat $objInputFile $PixelFormat $VideoCodec
		
		#get fonts
		Get-Fonts $objFFInfo $objInputFile $objTempFile

		#show duration
		Write-Host ("`nVideo Duration: " + $objInputFile.Duration.Sexagesimal + "`n")

		#show index selection
		Write-Host ("Video Index: " + $objInputFile.Index.Vid)

		If ($objInputFile.Index.Aud -gt -1) {
			Write-Host ("Audio Index: " + $objInputFile.Index.Aud)
		}
		If ($objInputFile.Index.Sub -gt -1) {
			Write-Host ("Subtitle Index: " + $objInputFile.Index.Sub)
		}
		
		#set ffmpeg's input / output frame rate options
		$objFROpts = Set-FrameRateOpts $objInputFile.FrameRate $objOutputFile.FrameRate $FrameRateIn
		
		#show frame rates
		Write-Host ("`nFrame Rate (Input | Output): {0} | {1}" -f $objInputFile.FrameRate.Fraction, $objFROpts.OutVal)

		#make an array to store all filterchains
		$objFilterChains = @()

		#build the main filterchain
		$objFilterChain = @()

		#make a deinterlace filter
		$objFilterDeint = Set-Deint $objInputFile $Deinterlace
		$objFilterChain += $objFilterDeint

		#make a crop filter
		$objFilterCrop = Set-Crop $objInputFile $objFilterChain[-1] $ForceCrop $NoCrop $MinRes
		$objFilterChain += $objFilterCrop

		#make a scale filter
		$objFilterScale = Set-Scale $objFFInfo $objInputFile $objFilterChain[-1] $Round $ForceRes $NoScale $MinRes $MaxRes
		$objFilterChain += $objFilterScale

		#make a subtitle filter
		$objFilterSubs = Set-Subs $objFFInfo $objInputFile $objFilterChain[-1] $objTempFile $ForceRes $Subs
		$objFilterChain += $objFilterSubs

		#remove unused filters from the chain
		$objFilterChain = $objFilterChain | Where-Object { $_.String }

		#if there are no filters, set up a null filter
		If (-not $objFilterChain) {
			$objFilterNull = [Filter]::new()
			$objFilterNull.String = 'null'

			$objFilterChain = @($objFilterNull)
		}

		#set the inputs and outputs of the main filterchain
		$strFilterChainInput = '0:{0}' -f $objInputFile.Index.Vid
		$strFilterChainOutput = 'out'

		$objFilterChain = Set-FilterChainIO $objFilterChain $strFilterChainInput $strFilterChainOutput

		#construct the full filter string
		$objFilterChains += Get-FilterChainString $objFilterChain

		$objFilterChain | Where-Object { $_.FilterChain } | ForEach-Object {
			$objFilterChains += Get-FilterChainString $_.FilterChain
		}

		$strFilter = $objFilterChains -join ';'

		#show the filter string
		Write-Host ("`nFilter Chain: " + (Get-UnescapedFilter $strFilter))

		#show ffmpeg version
		Write-Host ("`n" + (& $strFFmpegPath -version | Select-Object -First 1).Trim())

		#encode video
		Write-Host -ForegroundColor Green "`nEncoding video"

		#show probing message
		Write-Host -NoNewLine "Probing video. Please wait...`r"

		#if we do not have a valid audio index, encode video only and continue
		If ($objInputFile.Index.Aud -eq -1) {
			& $strFFmpegPath -y -loglevel $LogLevel -stats -forced_subs_only ([int]$ForcedSubsOnly.ToBool()) $objFROpts.InOpt $objFROpts.InVal -i $objInputFile.FullName $objFROpts.OutOpt $objFROpts.OutVal -c:v $VideoCodec -preset:v $VideoPreset -x265-params log-level=error -pix_fmt $objOutputFile.PixelFormat -crf:v $CRF -map [out] -filter_complex $strFilter -map_metadata -1 -map_chapters -1 $objTempFile.MP4

			#mux video
			Write-Host -ForegroundColor Green "`nMuxing"
			New-Item -Path $objOutputFile.Directory -Type Directory -ErrorAction SilentlyContinue | Out-Null
			& $strMP4BoxPath -add $objTempFile.MP4 -new $objOutputFile.FullName

			Continue
		}

		#otherwise, we have a valid audio index, so encode video and audio
		& $strFFmpegPath -y -loglevel $LogLevel -stats -forced_subs_only ([int]$ForcedSubsOnly.ToBool()) $objFROpts.InOpt $objFROpts.InVal -i $objInputFile.FullName $objFROpts.OutOpt $objFROpts.OutVal -c:v $VideoCodec -preset:v $VideoPreset -x265-params log-level=error -pix_fmt $objOutputFile.PixelFormat -crf:v $CRF -map [out] -filter_complex $strFilter -map_metadata -1 -map_chapters -1 $objTempFile.MP4 `
			-map 0:$($objInputFile.Index.Aud) -c:a flac -map_metadata -1 -map_chapters -1 -compression_level 0 -af aformat=sample_fmts=s16:channel_layouts=stereo:sample_rates=48000 $objTempFile.FLAC

		#encode audio
		Write-Host -ForegroundColor Green "`nEncoding audio"
		& $strQaacPath $objTempFile.FLAC -V($AudioQuality) -q 2 -o $objTempFile.M4A

		#apply gain
		If (-not $NoNormalize) {
			Write-Host -ForegroundColor Green "`nApplying ReplayGain"
			& $strAACGainPath /r /k $objTempFile.M4A
		}

		# mux video / audio
		Write-Host -ForegroundColor Green "`nMuxing"
		New-Item -Path $objOutputFile.Directory -Type Directory -ErrorAction SilentlyContinue | Out-Null
		& $strMP4BoxPath -add $objTempFile.MP4 -add $objTempFile.M4A -new $objOutputFile.FullName
	}
	Finally {
		#increment processed file counter
		$intFileCount++
		
		#always remove temporary files before finishing
		Remove-TempFiles $objTempFile
		
		###HACK TO ALLOW LEGACY COMMAND PARSING FOR NOW###
		$PSNativeCommandArgumentPassing = $PSNativeCommandArgumentPassingOrig
	}
}

#show completed message if needed
If (-not $HideProgress) {
	Write-Host "`nComplete."
}
