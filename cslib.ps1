Class InputFile {
	[string]$FullName
	[string]$BaseName
	[string]$Extension
	[string]$Directory
	[Index]$Index = [Index]::new()
	[Duration]$Duration = [Duration]::new()
	[FrameRate]$FrameRate = [FrameRate]::new()
	[Resolution]$Resolution = [Resolution]::new()
	[string]$PixelFormat
}

Class OutputFile {
	[string]$FullName
	[string]$BaseName
	[string]$BaseNameClean
	[string]$Directory
	[string]$Extension
	[FrameRate]$FrameRate
	[string]$PixelFormat
}

Class BaseName {
	[string] hidden $BaseName
	[string]$Clean

	BaseName (
		[string]$BaseName,
		[string]$Replace
	) {
		$This.BaseName = $BaseName
		$This.Clean = Clean-BaseName $BaseName $Replace
	}

	[string]ToString() {
		Return $This.BaseName
	}
}

Class Index {
	[int]$Vid = -1
	[int]$Aud = -1
	[int]$Sub = -1
}

Class FrameRate {
	[decimal]$Decimal
	[string]$Fraction
	[string]$Mode
	[bool]$IsInput

	FrameRate() {}

	FrameRate([string]$Input, [bool]$IsInput) {
		$This.IsInput = $IsInput
		
		#if we have specified vfr mode
		If ($Input -eq 'vfr') {
			#set the mode to vfr
			$This.Mode = $Input
		}
		#check if the input is fractional
		#the fraction will always be valid because of Check-FrameRate
		ElseIf ($Input -match '/') {
			$This.Fraction = $Input
			
			#always round the decimal representation to 3 decimal places
			$arrFraction = $Input.Split('/')
			$This.Decimal = [Math]::Round(([int]$arrFraction[0] / [int]$arrFraction[1]), 3)
			
			$This.Mode = 'cfr'
		}
		#otherwise, the input is decimal
		Else {
			#always round the decimal representation to 3 decimal places
			#this allows the fractional representation to always use integers when using 1000 as the denominator
			$This.Decimal = [Math]::Round($Input, 3)
		
			#make the fractional representation always use integers
			$This.Fraction = '{0}/1000' -f [Math]::Round(($This.Decimal * 1000))
			
			$This.Mode = 'cfr'
		}
	}

	[string]ToString() {
		#the format operator rounds automatically
		Return '{0:n3}' -f $This.Decimal
	}

	[void]SetToFieldRate() {
		#if we are in variable frame rate mode
		If ($This.Mode -eq 'vfr') {
			#do nothing
			Return
		}
		
		#always round the decimal representation to 3 decimal places
		$This.Decimal = [Math]::Round(($This.Decimal * 2), 3)
		
		#the fraction will always use integers because of Check-FrameRate
		#additionally, this can only be performed after the object has been created
		#meaning it will always use integers based on what the constructors do
		$arrFraction = $This.Fraction.Split('/')
		$This.Fraction =  '{0}/{1}' -f ([int]$arrFraction[0] * 2), $arrFraction[1]

		Return
	}
}

Class Duration {
	[float]$Seconds
	[string]$Sexagesimal

	Duration () {
		$This.Sexagesimal = '00:00:00.000'
	}

	Duration (
		[string]$Duration
	) {
		#converting values always ensures the duration is in the correct format
		If (-not ($Duration -as [decimal])) {
			$This.Seconds = Convert-FromSexagesimal $Duration
			$This.Sexagesimal = Convert-ToSexagesimal $This.Seconds
		}
		Else {
			$This.Sexagesimal = Convert-ToSexagesimal $Duration
			$This.Seconds = Convert-FromSexagesimal $This.Sexagesimal
		}
	}

	[string] ToString() {
		Return $This.Sexagesimal
	}
}

Class Resolution {
	[int]$Width
	[int]$Height

	Resolution () {}

	Resolution (
		[int]$Width,
		[int]$Height
	) {
		$This.Width = $Width
		$This.Height = $Height
	}

	[string]ToString() {
		Return 'Width : {0}, Height : {1}' -f $This.Width, $This.Height
	}
}

Class Filter {
	[string]$String
	[Resolution]$InputRes = [Resolution]::new()
	[Resolution]$OutputRes = [Resolution]::new()
	[string[]]$Inputs
	[string[]]$Outputs
	[Filter[]]$FilterChain = @()

	[string]ToString() {
		Return $This.String
	}

	Filter() {}

	Filter([Filter]$objFilter) {
		$This.InputRes.Width = $objFilter.OutputRes.Width
		$This.InputRes.Height = $objFilter.OutputRes.Height
		$This.OutputRes.Width = $objFilter.OutputRes.Width
		$This.OutputRes.Height = $objFilter.OutputRes.Height
	}

	Filter([Resolution]$Resolution) {
		$This.InputRes.Width = $Resolution.Width
		$This.InputRes.Height = $Resolution.Height
		$This.OutputRes.Width = $Resolution.Width
		$This.OutputRes.Height = $Resolution.Height
	}

	Filter(
		[InputFile]$objInputFile,
		[string]$String
	) {
		$This.String = $String
		$This.InputRes.Width = $objInputFile.Resolution.Width
		$This.InputRes.Height = $objInputFile.Resolution.Height
		$This.OutputRes.Width = $objInputFile.Resolution.Width
		$This.OutputRes.Height = $objInputFile.Resolution.Height
	}
}

Class Scrape {
	[string] hidden $BaseNameClean
	[Series]$Series = [Series]::new()
	[int]$Season
	[int]$Episode
	[string]$Title
	[string]$Language
	[bool]$Success

	Scrape() {}

	Scrape (
		[string]$BaseNameClean,
		[int]$SeriesID,
		[string]$Series,
		[int]$Season,
		[int]$Episode,
		[string]$Language
	) {
		$This.BaseNameClean = $BaseNameClean
		$This.Series.ID = $SeriesID
		$This.Season = $Season
		$This.Episode = $Episode
		$This.Language = $Language

		#use the series name if we have it already
		If ($Series) {
			$This.Series.Name = $Series
		}

		#if we have don't have a regex match, fail and exit
		$regPattern = [regex]::new('(s|S)\d{1,2}(e|E)\d{1,2}')
		$objMatch = $regPattern.Match($BaseNameClean)
		If (-not $objMatch.Success) {
			Write-Warning ("Could not match cleaned input name: '" + $BaseNameClean + "' for scraping. Try to match the format: 'Show Title S01E01'")
			Return
		}

		#otherwise, fill out the remaining properties
		If (-not $This.Series.Name) {
			$This.Series.Name = ($BaseNameClean -split $objMatch.Value)[0].Trim()
		}

		$arrMatches = $objMatch.Value.ToLower().TrimStart('s').Split('e')

		If ($This.Season -eq -1) {
			$This.Season = [int]$arrMatches[0]
		}

		If ($This.Episode -eq -1) {
			$This.Episode = [int]$arrMatches[1]
		}

		$This.Series = Scrape-Series $This
		$This.Series.Name = Normalize-Name $This.Series.Name

		#if we still don't have a valid seriesid, exit
		If ($This.Series.ID -eq -1) {
			Return
		}

		$This.Title = Scrape-Title $This
		$This.Title = Normalize-Name $This.Title


		$This.Success = $True
	}
}

Class Series {
	[string]$Name
	[int]$ID

	Series () {}

	Series (
		[string]$Name,
		[int]$ID
	) {
		$This.Name = $Name
		$This.ID = $ID
	}

	[string]ToString() {
		Return 'Name : {0}, ID : {1}' -f $This.Name, $This.ID
	}
}

Class TempFile {
	[string]$InputPath
	[string]$BaseName
	[string]$MP4
	[string]$FLAC
	[string]$M4A
	[string]$ASS
	[string]$Directory
	
	TempFile () {}

	TempFile (
		[string]$InputPath
	) {
		$This.BaseName = Get-StringHash $InputPath 16
		$This.MP4 = '{0}\{1}.mp4' -f $PSScriptRoot, $This.BaseName
		$This.FLAC = '{0}\{1}.flac' -f $PSScriptRoot, $This.BaseName
		$This.M4A = '{0}\{1}.m4a' -f $PSScriptRoot, $This.BaseName
		$This.ASS = '{0}\{1}.ass' -f $PSScriptRoot, $This.BaseName
		$This.Directory = '{0}\{1}' -f $PSScriptRoot, $This.BaseName
	}
}

Class FrameRateOpts {
	[string]$InOpt
	[string]$InVal
	[string]$OutOpt
	[string]$OutVal
	
	FrameRateOpts () {}
	
	FrameRateOpts (
		[string]$InOpt,
		[string]$InVal,
		[string]$OutOpt,
		[string]$OutVal
	) {
		$This.InOpt = $InOpt
		$This.InVal = $InVal
		$This.OutOpt = $OutOpt
		$This.OutVal = $OutVal
	}
}

Function Get-VideoResolution ($objFFInfo, $objInputFile) {
	#get width and height
	$intWidth = ($objFFInfo.streams[$objInputFile.index.Vid]).width
	$intHeight = ($objFFInfo.streams[$objInputFile.index.Vid]).height

	Return [Resolution]::new($intWidth, $intHeight)
}

Function Get-VideoDuration ($objFFInfo, $objInputFile) {
	#use the video duration metadata if it is available
	$strDuration = $objFFInfo.streams[$objInputFile.Index.Vid].duration
	If ($strDuration) {
		Return [Duration]::new($strDuration)
	}
	
	#use the video stream duration tag if it is available
	$strDuration = $objFFInfo.streams[$objInputFile.Index.Vid].tags | Select-Object -ExpandProperty DURATION* -First 1 -ErrorAction SilentlyContinue
	If ($strDuration) {
		Return [Duration]::new($strDuration)
	}

	#otherwise, use the container duration
	Return [Duration]::new($objFFInfo.Format.Duration)
}

Function Get-InputFrameRate ($objFFInfo, $objInputFile, $strFrameRate) {
	#if the frame rate is manually defined
	If ($strFrameRate -ne 'auto') {
		Return [FrameRate]::New($strFrameRate, $True)
	}
	
	#otherwise, use the video stream metadata
	$strFrameRate = [string]$objFFInfo.Streams[$objInputFile.Index.Vid].r_frame_rate
	Return [FrameRate]::new($strFrameRate, $True)
}

Function Set-OutputFrameRate ($objInputFile, $strFrameRate, $intDeinterlace) {
	#if the frame rate is manually defined
	If ($strFrameRate -ne 'auto') {
		$objFrameRate = [FrameRate]::New($strFrameRate, $False)
	}
	Else {
		#otherwise, use the input frame rate
		$objFrameRate = [FrameRate]::New($objInputFile.FrameRate.Fraction, $False)
		
		#make sure the output frame rate matches common standards
		#make a hash table of standard frame rates, they must be ordered from lowest to highest
		$hashCommonFrameRates = [ordered]@{
			'24000/1001' = 23.976
			'24/1' = 24
			'25/1' = 25
			'30000/1001' = 29.97
			'30/1' = 30
			'60000/1001' = 59.97
			'60/1' = 60
		}
		
		#if we have an uncommon frame rate
		If ($hashCommonFrameRates.Values -notcontains [decimal]$objFrameRate.Decimal) {
			Write-Warning ('Non-standard input frame rate: ({0}).' -f $objFrameRate.Fraction)
			
			$objCommonFrameRateEntry = $hashCommonFrameRates.GetEnumerator() | Where-Object {-not ($objFrameRate.Decimal % [decimal]$_.Value)} | Select-Object -First 1
			
			If ($objCommonFrameRateEntry) {
				Write-Warning ('Switching output frame rate to lowest common frame rate: ({0}).' -f $strCommonFrameRate.Key)
				$objFrameRate.Fraction = $strCommonFrameRate.Key
				$objFrameRate.Decimal = $objCommonFrameRateEntry.Value
				$objFrameRate.Mode = 'cfr'
			}
			Else {
				Write-Warning ('Switching to variable frame rate output.')
				$objFrameRate.Mode = 'vfr'
			}
		}
	}
	
	#if we are deinterlacing in yadif mode 1, set the frame rate to the field rate (double the frame rate)
	If ($intDeinterlace -eq 2) {
		$objFrameRate.SetToFieldRate()
	}

	Return $objFrameRate
}

Function Get-VideoIndex ($objFFInfo, $VideoIndex) {
	#get a list of video streams
	$objVideoStreams = $objFFInfo.streams | Where-Object {($_.codec_type -eq 'video') -and ($_.disposition.attached_pic -ne 1) -and ($_.disposition.still_image -eq 0)}

	#no video streams
	If (-not $objVideoStreams) {
		Return -1
	}

	#use manually defined video index
	If ($VideoIndex -ne -1) {
		$intVideoIndex = ($objVideoStreams | Where-Object {$_.index -eq $VideoIndex}).index
		If ($intVideoIndex -ne $Null) {
			Return $intVideoIndex
		}
	}

	#use container default video stream
	$intDefaultIndex = ($objVideoStreams | Where-Object {$_.disposition.default -eq 1}).index | Select-Object -First 1
	If ($intDefaultIndex -ne $Null) {
		Return $intDefaultIndex
	}

	#use first highest resolution stream
	$intHighestRes = 0
	$objVideoStreams | ForEach {
		$intStreamRes = $_.width * $_.height
		If ($intStreamRes -gt $intHighestRes) {
			$intHighestRes = $intStreamRes
			$intResIndex = $_.index
		}
	}

	Return $intResIndex
}

Function Get-SubIndex ($objFFInfo, $SubIndex, $SubLang, $SubTitle, $Subs) {
	#subtitles disabled
	If (-not $Subs) {
		Return -1
	}

	#get a list of subtitle streams
	$objSubStreams = $objFFInfo.streams | Where-Object {$_.codec_type -eq 'subtitle'}

	#no subtitle streams
	If ($objSubStreams -eq $Null) {
		Return -1
	}

	#if the subtitle index is manually defined
	If ($SubIndex -ne -1) {
		$intSubIndex = ($objSubStreams | Where-Object {$_.index -eq $SubIndex}).index
		If ($intSubIndex -ne $Null) {
			Return $intSubIndex
		}
	}

	#use subtitle title
	If ($SubTitle) {
		$intTitleIndex = ($objSubStreams | Where-Object {$_.tags.title -eq $SubTitle}).index | Select-Object -First 1
		If ($intTitleIndex -ne $Null) {
			Return $intTitleIndex
		}
	}

	#use subtitle language
	If ($SubLang -ne $Null) {
		$intLangIndex = ($objSubStreams | Where-Object {$_.tags.language -eq $SubLang}).index | Select-Object -First 1
		If ($intLangIndex -ne $Null) {
			Return $intLangIndex
		}
	}

	#use container default subtitle stream
	$intDefaultIndex = ($objSubStreams | Where-Object {$_.disposition.default -eq 1}).index | Select-Object -First 1
	If ($intDefaultIndex -ne $Null) {
		Return $intDefaultIndex
	}

	#use any subtitle stream
	$intAnyIndex = ($objSubStreams | Select-Object -First 1).index
	If ($intAnyIndex -ne $Null) {
		Return $intAnyIndex
	}
}

Function Get-AudioIndex ($objFFinfo, $AudioIndex, $AudioLang, $AudioTitle, $NoAudio) {
	#audio disabled
	If ($NoAudio) {
		Return -1
	}

	#get a list of audio streams
	$objAudioStreams = $objFFInfo.streams | Where-Object {$_.codec_type -eq 'audio'}

	#no audio streams
	If ($objAudioStreams -eq $Null) {
		Return -1
	}

	#use manually defined audio index
	If ($AudioIndex -ne -1) {
		$intAudioIndex = ($objAudioStreams | Where-Object {$_.index -eq $AudioIndex}).index
		If ($intAudioIndex -ne $Null) {
			Return $intAudioIndex
		}
	}

	#use audio title
	If ($AudioTitle) {
		$intTitleIndex = ($objAudioStreams | Where-Object {$_.tags.title -eq $AudioTitle}).index | Select-Object -First 1
		If ($intTitleIndex -ne $Null) {
			Return $intTitleIndex
		}
	}

	#use audio language
	If ($AudioLang -ne $Null) {
		$intLangIndex = ($objAudioStreams | Where-Object {$_.tags.language -eq $AudioLang}).index | Select-Object -First 1
		If ($intLangIndex -ne $Null) {
			Return $intLangIndex
		}
	}

	#use container default audio stream
	$intDefaultIndex = ($objAudioStreams | Where-Object {$_.disposition.default -eq 1}).index | Select-Object -First 1
	If ($intDefaultIndex -ne $Null) {
		Return $intDefaultIndex
	}

	#use any audio stream
	$AudioIndex = ($objAudioStreams | Select-Object -First 1).index
	If ($AudioIndex -ne $Null) {
		Return $AudioIndex
	}
}

Function Set-Deint ($objInputFile, $intDeint) {
	If ($intDeint -eq 1) {
		$strDeint = 'yadif=0'
	}

	If ($intDeint -eq 2) {
		$strDeint = 'yadif=1'
	}

	#return filter object
	Return [Filter]::new($objInputFile, $strDeint)
}

#set cropping values for chosen video stream
Function Set-Crop ($objInputFile, $objPrevFilter, $ForceCrop, $NoCrop, $MinRes) {
	#set properties for crop filter
	$objFilterCrop = [Filter]::new($objPrevFilter.OutputRes)
	
	#abort crop if needed
	If ($NoCrop) {
		Return $objFilterCrop
	}

	#declare input width and height
	$intInputWidth = $objFilterCrop.OutputRes.Width
	$intInputHeight = $objFilterCrop.OutputRes.Height
	
	#get minimum resolution values (used in forced crop and auto crop)
	$arrMinRes = $MinRes.Split('x')
	$intMinWidth = [int]$arrMinRes[0]
	$intMinHeight = [int]$arrMinRes[1]

	#check if forced crop is enabled and valid
	If ($ForceCrop) {
		#get crop values, explictly cast to an array of integers, as split() always returns an array of strings
		$arrForceCrop = [int[]]($ForceCrop.Split(':'))
		$intForceWidth = $arrForceCrop[0] + $arrForceCrop[2]
		$intForceHeight = $arrForceCrop[1] + $arrForceCrop[3]

		#if forced crop is within width / height bounds, use it
		If (($intForceWidth -le $intInputWidth) -and ($intForceHeight -le $intInputHeight) -and ($intForceWidth -ge $intMinWidth) -and ($intForceHeight -ge $intMinHeight)) {
			$objFilterCrop.String = 'crop=' + $ForceCrop
			$objFilterCrop.OutputRes.Width = $intForceWidth
			$objFilterCrop.OutputRes.Height = $intForceHeight

			Return $objFilterCrop
		}
		#otherwise, show a warning, then run auto crop anyway
		Else {
			Write-Warning ('Forced crop: {0} is out of bounds, using auto-crop.' -f $ForceCrop)
		}
	}

	#start auto cropping
	$objCropList = New-Object System.Collections.Generic.List[string]
	$intTotalIterations = 10
	$intFrameAmt = [Math]::Round($objInputFile.FrameRate.Decimal, 0)
	$floatCropConfidenceThreshhold = 66.7

	#ensure video is long enough to perform auto-crop
	If (($objInputFile.FrameRate.Decimal * $objInputFile.Duration.Seconds) -lt ($intFrameAmt * $intTotalIterations)) {
		Write-Warning ('Video duration is too short: {0}. Auto-crop filter bypassed.' -f $objInputFile.Duration.Sexagesimal)
		
		Return $objFilterCrop
	}

	
	$floatSeekChunk = $objInputFile.Duration.Seconds / $intTotalIterations

	#run auto crop
	$intCropCounter = 0
	While ($intCropCounter -lt $intTotalIterations) {
		$intSeekSeconds =  $intCropCounter * $floatSeekChunk

		#run ffmpeg
		$strCropDetect = & $strFFmpegPath -skip_frame noref -vsync 0 -ss $intSeekSeconds -i $objInputFile.FullName -map ('0:' + $objInputFile.Index.Vid) -frames $intFrameAmt -vf cropdetect=limit=24:round=4 -f null nul 2>&1
		
		#split ffmpeg output string to get crop parameters
		$strCrop = [regex]::Split([regex]::Split($strCropDetect, 'crop=')[-1], "`r`n")[0].Trim()
		$strCrop = $strCrop.Split("frame=")[0].Trim()
		
		#add to the crop list if there are no errors
		If ($strCrop -match '^([0-9]+):([0-9]+):([0-9]+):([0-9]+)$') {
			#add current crop value to crop list
			$objCropList.Add($strCrop)
		}

		#calculate / format progress percentage
		$floatProgress = (([int]$intCropCounter / [int]($intTotalIterations - 1)) * 100).ToString("0.0")

		#display progress
		$strProgress = "`rAuto-cropping [$floatProgress%]"
		Write-Host $strProgress -NoNewLine

		#remove the carriage return from the beginning of the progress string
		$strProgress = $strProgress -replace '\r',''

		$intCropCounter++
	}

	Write-Host ("`r{0}`r" -f (' ' * $strProgress.Length)) -NoNewLine

	#make sure cropping confidence is greater than 50%
	#get the most common cropping value
	$objCrop = $objCropList | Group-Object | Sort-Object Count -Descending | Select-Object -First 1
	
	[float]$floatCropConfidence = ($objCrop.Count / $intTotalIterations) * 100
	
	#get the most common auto-crop string
	$strCrop = $objCrop | Select-Object -ExpandProperty Name -First 1
	
	#check if our crop is invalid
	If (-not $strCrop) {
		Write-Warning ('Auto-crop is invalid. No crop data found. Auto-crop filter bypassed.' -f $strCrop)
		$objFilterCrop.String = $Null
		Return $objFilterCrop
	}

	#get output height and width
	$arrCrop = $strCrop.Split(':')
	$intOutputWidth = [int]$arrCrop[0]
	$intOutputHeight = [int]$arrCrop[1]
	
	#first, check if we have enough data points
	$intMinimumDataPoints = [int]($intTotalIterations * 0.8)
	If ($objCropList.Count -lt $intMinimumDataPoints) {
		Write-Warning ('Auto-crop did not collect enough data points: {0} of {1}. Auto-crop filter bypassed.' -f $objCropList.Count, $intMinimumDataPoints)
		$objFilterCrop.String = $Null
		Return $objFilterCrop
	}
	
	#next, check if our crop is invalid
	If (($intOutputWidth -le $intMinWidth) -or ($intOutputHeight -le $intMinHeight)) {
		Write-Warning ('Auto-crop is invalid: {0}. Auto-crop filter bypassed.' -f $strCrop)
		$objFilterCrop.String = $Null
		Return $objFilterCrop
	}
	
	#next, check if nothing changed
	If (($intInputWidth -eq $intOutputWidth) -and ($intInputHeight -eq $intOutputHeight)) {
		$objFilterCrop.String = $Null
		Return $objFilterCrop
	}
	
	#next, check if are are confident in our auto crop
	If (($floatCropConfidence -lt $floatCropConfidenceThreshhold) -and ($intCropBypass -eq 0)) {
		Write-Warning ("Auto-crop confidence is below $floatCropConfidenceThreshhold% (" + ("{0:n1}" -f $floatCropConfidence) + "%). Auto-crop filter bypassed.")
		$objFilterCrop.String = $Null
		Return $objFilterCrop
	}

	#fill out filter values
	$objFilterCrop.String = ('crop=' + $strCrop)
	$objFilterCrop.OutputRes.Width = $intOutputWidth
	$objFilterCrop.OutputRes.Height = $intOutputHeight

	Return $objFilterCrop
}

#sets scaling for chosen video stream
Function Set-Scale ($objFFInfo, $objInputFile, $objPrevFilter, $Round, $ForceRes, $NoScale, $MinRes, $MaxRes) {
	$objScaleFilter = [Filter]::new($objPrevFilter.OutputRes)

	#check if scaling is disabled
	If ($NoScale) {
		Return $objScaleFilter
	}

	#get the minimum allowed resolution
	$arrMinRes = $MinRes.ToLower().Split('x')
	$intMinWidth = [int]$arrMinRes[0]
	$intMinHeight = [int]$arrMinRes[1]

	#if forced resolution is defined
	If ($ForceRes) {
		#if the forced resolution is outside of the minimum width / height, skip scaling
		$arrForceRes = $ForceRes.ToLower().Split('x')
		$intForceWidth = [int]$arrForceRes[0]
		$intForceHeight = [int]$arrForceRes[1]

		If (($intForceWidth -lt $intMinWidth) -or ($intForceHeight -lt $intMinHeight)) {
			Write-Warning ('Forced resolution: {0} is smaller than the allowed minimum: {1}. Scale filter bypassed.' -f $ForceRes, $MinRes)
			$objScaleFilter.String = $Null

			Return $objScaleFilter
		}

		$objScaleFilter.String = 'scale={0}:{1},setsar=1' -f $intForceWidth, $intForceHeight
		$objScaleFilter.OutputRes.Width = $intForceWidth
		$objScaleFilter.OutputRes.Height = $intForceHeight

		Return $objScaleFilter
	}

	#get the input width and height
	$intInputWidth = [int]$objScaleFilter.InputRes.Width
	$intInputHeight = [int]$objScaleFilter.InputRes.Height

	#get maximum width / height
	$arrMaxRes = $MaxRes.Split('x')
	$intMaxWidth = [int]$arrMaxRes[0]
	$intMaxHeight = [int]$arrMaxRes[1]
	
	#get the input display aspect ratio
	$strInputFileDAR = $objFFInfo.streams[$objInputFile.Index.Vid].display_aspect_ratio
	
	#if the display aspect ratio exists, we cannot assume square pixels
	If ($strInputFileDAR) {
		#force square pixels
		#PAR = DAR / SAR
		#DAR = PAR * SAR
		#SAR = DAR / PAR
		#SAR = W / H
		
		#get the input file display aspect ratio
		$arrInputFileDAR = $objFFInfo.streams[$objInputFile.Index.Vid].display_aspect_ratio.Split(':')
		$floatInputFileDAR = [float]$arrInputFileDAR[0] / [float]$arrInputFileDAR[1]
		
		#get the input file pixel aspect ratio
		$floatInputFilePAR = $floatInputFileDAR / ($objInputFile.Resolution.Width / $objInputFile.Resolution.Height)
		
		#calculate the filter's new display aspect ratio using the input file pixel aspect ratio
		$floatDAR = $floatInputFilePAR * ($intInputWidth / $intInputHeight)

		#force the output to have square pixels
		#if the input pixel aspect ratio is greater than or equal to 1
		#this means the pixels are wider than they are high, or are already square
		If ($floatInputFilePAR -ge 1.0) {
			#upscale the width
			$floatOutputWidth = $intInputWidth * $floatInputFilePAR
			$floatOutputHeight = $intInputHeight
		}
		#otherwise, the pixels are higher than they are wide
		Else {
			#upscale the height
			$floatOutputWidth = $intInputWidth
			$floatOutputHeight = $intInputHeight / $floatInputFilePAR
		}
	}
	#otherwise we have to assume square pixels, just use the filter's input resolution
	Else {
		#when we have square pixels, DAR = SAR = W / H
		$floatDAR = $intInputWidth / $intInputHeight
		$floatOutputWidth = $intInputWidth
		$floatOutputHeight = $intInputHeight
	}
	
	#scale the image so it does not exceed the maximum resolution
	#if the output width is greater than or equal to the output height
	If ($floatOutputWidth -ge $floatOutputHeight) {
		If ($floatOutputWidth -gt $intMaxWidth) {
			#downscale according to the max input width
			$floatOutputWidth = $intMaxWidth
			$floatOutputHeight = $floatOutputWidth / $floatDAR
		}
	}
	#otherwise, the output width is less than the output height
	Else {
		If ($floatOutputHeight -gt $intMaxHeight) {
			#downscale according to the max output height
			$floatOutputHeight = $intMaxHeight
			$floatOutputWidth = $floatOutputHeight * $floatDAR
		}
	}
	
	#quantize the output values to the user defined 'Round' parameter
	$intOutputWidth = [int](Round-Value $floatOutputWidth $Round)
	$intOutputHeight = [int](Round-Value $floatOutputHeight $Round)
	
	#if the output width is greater than the max width, this is possible due to quantization
	If ($intOutputWidth -gt $intMaxWidth) {
		#decrease the output width by the round amount
		$intOutputWidth -= $Round
	}
	
	#if the output height is greater than the max height
	If ($intOutputHeight -gt $intMaxHeight) {
		#decrease the output height by the round amount
		$intOutputHeight -= $Round
	}

	#do nothing if input width / height is equal to output width / height
	If (($intInputHeight -eq $intOutputHeight) -and ($intInputWidth -eq $intOutputWidth)) {
		$objScaleFilter.String = $Null

		Return $objScaleFilter
	}

	#skip scaling if scaled width / height is less than minimum width / height
	If (($intOutputWidth -lt $intMinWidth) -or ($intOutputHeight -lt $intMinHeight)) {
		Write-Warning ('Scaled resolution: {0}x{1}, is smaller than the allowed minimum: {2}. Scale filter bypassed.' -f $intOutputWidth, $intOutputHeight, $MinRes)
		$objScaleFilter.String = $Null

		Return $objScaleFilter
	}

	#fill out filter values
	$objScaleFilter.OutputRes.Width = $intOutputWidth
	$objScaleFilter.OutputRes.Height = $intOutputHeight

	$strScaleAlgo = Get-ScaleAlgo $intInputWidth $intInputHeight $intOutputWidth $intOutputHeight
	$objScaleFilter.String = 'scale={0}:{1}:{2}' -f $objScaleFilter.OutputRes.Width, $objScaleFilter.OutputRes.Height, $strScaleAlgo

	Return $objScaleFilter
}

#set up the subtitle filter
Function Set-Subs ($objFFInfo, $objInputFile, $objPrevFilter, $objTempFile, $ForceRes, $Subs) {
	#construct filter object
	$objSubFilter = [Filter]::new($objPrevFilter)

	#no subs found or subs disabled
	If ($objInputFile.Index.Sub -eq -1) {
		Return $objSubFilter
	}

	#make a list of pgs codecs
	$arrPGSCodecs = @('hdmv_pgs_subtitle', 'dvd_subtitle')

	#get the current sub codec
	$strSubCodec = $objFFinfo.streams[$objInputFile.Index.Sub].codec_name

	#check if the current sub codec is in the pgs sub list
	If ($strSubCodec -in $arrPGSCodecs) {
		#if the output resolution does not match the original, we need to set up a secondary filterchain to
		#scale the subtitles as necessary
		$intInputWidth = $objInputFile.Resolution.Width
		$intInputHeight = $objInputFile.Resolution.Height
		$intOutputWidth = $objSubFilter.InputRes.Width
		$intOutputHeight = $objSubFilter.InputRes.Height
		$strScaleAlgo = Get-ScaleAlgo $intInputWidth $intInputHeight $intOutputWidth $intOutputHeight

		$objSubFilter.String = 'overlay'
		$strVidIndexInput = '0:{0}' -f $objInputFile.Index.Sub

		If (($intInputWidth -ne $intOutputWidth) -or ($intInputHeight -ne $intOutputHeight)) {
			$objSubScaleFilter = [Filter]::new()
			$objSubScaleFilter.String = 'scale={0}:{1}:{2}' -f $intOutputWidth, $intOutputHeight, $strScaleAlgo
			$objSubScaleFilter.InputRes.Width = $intInputWidth
			$objSubScaleFilter.InputRes.Height = $intInputHeight
			$objSubScaleFilter.OutputRes.Width = $intOutputWidth
			$objSubScaleFilter.OutputRes.Height = $intOutputHeight

			$objSubScaleFilter.Inputs = $strVidIndexInput
			$objSubScaleFilter.Outputs = 'subs'

			$objSubFilter.FilterChain += $objSubScaleFilter
			$objSubFilter.Inputs = 'subs'
		}
		Else {
			$objSubFilter.String = 'overlay'
			$objSubFilter.Inputs = $strVidIndexInput
		}

		Return $objSubFilter
	}

	#process normal subtitles
	[int[]]$arrSubFilterIndexes = $objFFInfo.streams | Where-Object {($_.codec_type -eq 'subtitle') -and ($_.codec_name -notin $arrPGSCodecs)} | Select-Object -ExpandProperty index
	$intSubFilterIndex = $arrSubFilterIndexes.IndexOf($objInputFile.Index.Sub)

	$strFullNameEsc = Escape-Filter $objInputFile.FullName
	
	#use the font path
	If (Test-Path -LiteralPath $objTempFile.Directory) {
		$strFontPathEsc = Escape-Filter $objTempFile.Directory
	}
	Else {
		$strFontPathEsc = Escape-Filter $PSScriptRoot
	}
	
	$strOrigSize = Get-PlayRes $objFFInfo $objInputFile $objSubFilter $objTempFile

	$strSubFilter = 'subtitles="{0}":fontsdir="{1}":si={2}:original_size={3}' -f $strFullNameEsc, $strFontPathEsc, $intSubFilterIndex, $strOrigSize

	#fill in filter string
	$objSubFilter.String = $strSubFilter

	Return $objSubFilter
}

Function Get-PlayRes ($objFFInfo, $objInputFile, $objSubFilter, $objTempFile) {
	$strInputRes = '{0}x{1}' -f $objInputFile.Resolution.Width, $objInputFile.Resolution.Height
	
	#if we are not using ass subtitles
	$strSubFormat = $objFFInfo.streams[$objInputFile.Index.Sub].codec_name
	If ($strSubFormat -ne 'ass') {
		#use the subtitle filter's input res
		Return '{0}x{1}' -f $objSubFilter.InputRes.Width, $objSubFilter.InputRes.Height
	}
		
	#extract the ass header info, this will always return a valid '[Script Info]' section
	& $strFFmpegPath -y -loglevel quiet -i $objInputFile.FullName -map 0:$($objInputFile.Index.Sub) -c copy -t 0 $objTempFile.ASS
	
	#get the content of the [Script Info] section
	$objASSContent = Get-Content -LiteralPath $objTempFile.ASS
	$strPlayResX = $objASSContent | Where-Object {$_ -imatch '^\s*?(PlayResX)\s*?:\s*?\d*?\s*?$'}
	$strPlayResY = $objASSContent | Where-Object {$_ -imatch '^\s*?(PlayResY)\s*?:\s*?\d*?\s*?$'}
	
	#if either of the playres strings do not exist
	If ([string]::IsNullOrEmpty($strPlayResX) -or [string]::IsNullOrEmpty($strPlayResY)) {
		#use input res
		Return $strInputRes
	}

	#get playres integers
	$intPlayResX = ($strPlayResX.Split(':')[1]) -as [int]
	$intPlayResY = ($strPlayResY.Split(':')[1]) -as [int]
	
	#if we dont have valid playres integers
	If (($intPlayResX -le 0) -or ($intPlayResY -le 0)) {
		#use input res
		Return $strInputRes
	}
	
	Return '{0}x{1}' -f $intPlayResX, $intPlayResY
}

Function Get-ScaleAlgo ($intInWidth, $intInHeight, $intOutWidth, $intOutHeight) {
	[int]$intInputRes = $intInWidth * $intInHeight
	[int]$intOutputRes = $intOutWidth * $intOutHeight

	If ($intInputRes -lt $intOutputRes) {
		Return 'bicubic'
	}

	Return 'bilinear'
}

Function Get-Fonts ($objFFInfo, $objInputFile, $objTempFile) {
	$objFontAttachments = $objFFInfo.streams | Where-Object {($_.codec_type -eq 'attachment') -and ($_.tags.mimetype -like '*font*')}

	If ((-not $objFontAttachments) -or ($objInputFile.SubIndex -eq -1)) {
		Return
	}

	Try {
		#create the font directory
		New-Item -Path $objTempFile.Directory -ItemType 'Directory' -ErrorAction SilentlyContinue | Out-Null

		#set the working directory to the temporary directory, as ffmpeg can only batch extract to the current directory
		$objCurrentLocation = Get-Location
		Set-Location -LiteralPath $objTempFile.Directory

		#extract fonts
		& $strFFmpegPath -y -loglevel quiet -dump_attachment:t `"`" -i $objInputFile.FullName
	}
	Catch {}
	Finally {
		Set-Location -LiteralPath $objCurrentLocation
	}
}

Function Set-FilterChainIO ($objFilterChain, $strFilterChainInput, $strFilterChainOutput) {
	$intFilterCounter = 0

	$objFilterChain | ForEach {
		#if we are on the first item, set the filterchain input as the first input
		If ($intFilterCounter -eq 0) {
			$_.Inputs = @($strFilterChainInput) + ($_.Inputs | Where-Object {$_})
		}
		Else {
			$_.Inputs = @($strFilterChainOutput) + ($_.Inputs | Where-Object {$_})
		}

		#if we are on the last item, set the filterchain output to the output
		If ($intFilterCounter -eq $objFilterChain.Count - 1) {
			$_.Outputs = @($strFilterChainOutput)
		}
		Else {
			$_.Outputs = @($strFilterChainOutput) + ($_.Outputs | Where-Object {$_})
		}

		$intFilterCounter++
	}

	Return $objFilterChain
}

Function Get-FilterChainString ($objFilterChain) {
	$arrFilterChain = @()
	$objFilterChain | ForEach {
		If ($_.String) {
			$strFilterInput =  '[{0}]' -f ($_.Inputs -join '][')
			$strFilterOutput = '[{0}]' -f ($_.Outputs -join '][')

			$arrFilterChain += '{0}{1}{2}' -f $strFilterInput, $_.String, $strFilterOutput
		}
	}

	$strFilterChain = $arrFilterChain -join ','

	Return $strFilterChain
}

#escape the subtitle video filter string so powershell interprets it correctly
Function Escape-Filter ($strInput) {
	#replace backslashes
	If ($strInput -match '\\') {$strInput=$strInput.Replace('\', '\\\\')}

	#replace colons
	If ($strInput -match ':') {$strInput=$strInput.Replace(':', '\\:')}

	#replace semicolons
	If ($strInput -match ';') {$strInput=$strInput.Replace(';', '\;')}

	#replace commas
	If ($strInput -match ',') {$strInput=$strInput.Replace(',', '\,')}

	#replace single quotes
	If ($strInput -match '''') {$strInput=$strInput.Replace('''', '\\\''')}

	#replace left square brackets
	If ($strInput -match '\[') {$strInput=$strInput.Replace('[', '\[')}

	#replace right square brackets
	If ($strInput -match '\]') {$strInput=$strInput.Replace(']', '\]')}

	#return the result
	Return $strInput
}

#unescape the subtitle video filter string so it can be displayed correctly
Function Unescape-Filter ($strInput) {
	#replace backslashes
	If ($strInput -match '\\') {$strInput = $strInput.Replace('\\\\', '\')}

	#replace colons
	If ($strInput -match ':') {$strInput = $strInput.Replace('\\:', ':')}

	#replace semicolons
	If ($strInput -match ';') {$strInput = $strInput.Replace('\;', ';')}

	#replace commas
	If ($strInput -match ',') {$strInput = $strInput.Replace('\,', ',')}

	#replace single quotes
	If ($strInput -match '''') {$strInput = $strInput.Replace('\\\''', '''')}

	#replace left square brackets
	If ($strInput -match '\[') {$strInput = $strInput.Replace('\[', '[')}

	#replace right square brackets
	If ($strInput -match '\]') {$strInput = $strInput.Replace('\]', ']')}

	#return the result
	Return $strInput
}

Function Scrape-Title ($objScrape) {
	#set the tvdb api variables
	$strKey = '6262A88CCAB7E724'
	$strOrder = 'default'

	#construct the scrape uri
	$arrURI = @($strKey, $objScrape.Series.ID, $strOrder, $objScrape.Season, $objScrape.Episode, $objScrape.Language)

	$strURI = 'http://www.thetvdb.com/api/{0}/series/{1}/{2}/{3}/{4}/{5}' -f $arrURI

	#try running the web request
	Try {
		$ProgressPreference = 'SilentlyContinue'
		$xmlInfo = [xml](Invoke-RestMethod $strURI -ErrorAction SilentlyContinue)
		$ProgressPreference = 'Continue'
	}
	#show a warning if scrape failed
	Catch {
		Write-Warning "Web request for Tile scrape failed."
		Return $Null
	}

	#return null / show a warning if no episode info was scraped
	If ($xmlInfo.Data.Episode.id -eq 0) {
		Write-Warning ("No Title scrape data found for: '" + $objScrape.Series.Name + "'")
		Return $Null
	}

	Return $xmlInfo.Data.Episode.EpisodeName
}

Function Scrape-Series ($objScrape) {
	#declare a default falure object to return
	$objScrapeFail = [Series]::new($objScrape.Series.Name, -1)

	#query the series name to get the series xml object
	$strURI = 'http://thetvdb.com/api/GetSeries.php?seriesname={0}' -f [uri]::EscapeDataString($objScrape.Series.Name)

	#try to scrape
	Try {
		$ProgressPreference = 'SilentlyContinue'
		$xmlInfo = [xml](Invoke-RestMethod $strURI -ErrorAction SilentlyContinue)
		$ProgressPreference = 'Continue'
	}
	#show warning if scrape failed
	Catch {
		Write-Warning "Web request for SeriesID scrape failed."
		Return $objScrapeFail
	}

	#show a warning if no series info was retrieved
	If (-not $xmlInfo.Data.Series) {
		Write-Warning ('No SeriesID scraped for: {0}' -f $objScrape.Series.Name)
		Return $objScrapeFail
	}

	#get the first series retreived
	$objSeries = @($xmlInfo.data.series)[0]

	#return a new series object with both the scraped seriesname and seriesid
	Return [Series]::new($objSeries.SeriesName,$objSeries.seriesid)
}

Function Get-OutputExtension ($strExtension, $boolNoEncode) {
	If ($boolNoEncode) {
		Return $strExtension
	}

	Return '.mp4'
}

Function Clean-BaseName ($strBaseName, $arrReplace) {
	#process any string replacements
	If ($arrReplace) {
		$arrReplace | ForEach {
			$arrElement = $_.Split(':')

			If ($arrElement[1]) {
				$strReplaceIn = [regex]::Escape($arrElement[0])
				$strReplaceOut = [regex]::Escape($arrElement[1])
			}

			$strBaseName = $strBaseName -ireplace $strReplaceIn, $strReplaceOut
		}

		$strBaseName = [regex]::Unescape($strBaseName)
	}

	#clean between '[' and ']'
	$strBaseName = $strBaseName -replace '\[.*?\](?![^\[\]]*\])', ''

	#clean between '(' and ')'
	$strBaseName = $strBaseName -replace '\(.*?\)(?![^\(\)]*\))', ''

	#replace '.' with ' '
	$strBaseName = $strBaseName.Replace('.', ' ')

	#replace '_' with ' '
	$strBaseName = $strBaseName.Replace('_', ' ')

	#convert to title case
	$strBaseName = (Get-Culture).TextInfo.ToTitleCase($strBaseName)

	#normalize name
	$strBaseName = Normalize-Name $strBaseName

	Return $strBaseName
}

Function Normalize-Name ($strInput) {
	#replace '–|—|−' with '-'
	$strInput = $strInput -replace '–|—|−', '-'

	#replace '’' with '''
	$strInput = $strInput -replace "’", "'"

	#replace '`'  with '''
	$strInput = $strInput -replace "``", "'"

	#replace ':' with '-'
	$strInput = $strInput -replace ':', '-'

	#replace '?' with '-' (this causes issues with mp4box)
	$strInput = $strInput -replace [regex]::Escape('?'), '-'
	
	#replace '/' with '-' (this causes issues with mp4box)
	$strInput = $strInput -replace '/', '-'
	
	#replace '"' with ''''
	$strInput = $strInput -replace '"', "''"

	#remove any accented characters
	[char[]]$strInput.Normalize('FormD') | ForEach {
		If ([System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($_) -ne 'NonSpacingMark') {
			$strNoAccents = $strNoAccents + $_
		}
	}
	$strInput = $strNoAccents

	#replace invalid file system characters with '-'
	$strInvalidChars = [IO.Path]::GetInvalidFileNameChars() -join ''
	$strInput = $strInput -replace [regex]::Escape($strInvalidChars), '-'

	#trim whitespace from either end of the input string
	$strInput = $strInput.Trim()

	#convert multiple spaces to single spaces
	$strInput = $strInput -replace '\s+', ' '

	Return $strInput
}

#process parameters defined in ini file
Function Process-INI ($INIPath, $objParamKeys) {
	#no ini file defined
	If (-not $INIPath) {
		Return
	}

	#gather parameters from ini file, skipping comments / blank lines
	$hashINIContent = Get-Content -LiteralPath $INIPath | Where-Object {(($_) -and ($_.Trim)) -and ($_.Trim() -notmatch '^\;')} | Out-String | ConvertFrom-StringData

	#iterate through all existing parameters, overwriting with existing ini values
	ForEach ($objKey In $objParamKeys) {
		#get the current parameter
		$objParam = Get-Variable -Scope Script -Name $objKey -ErrorAction SilentlyContinue

		If (-not $objParam) {
			Continue
		}

		If (-not $hashINIContent.ContainsKey($objKey)) {
			Continue
		}

		#if it is a switch parameter, process as needed
		If ($objParam.Value -is [System.Management.Automation.SwitchParameter]) {
			Set-Variable -Scope Script -Name $objKey -Value (Convert-StringToBool $hashINIContent."$objKey")

			Continue
		}

		#otherwise, the parameter does not require processing
		Set-Variable -Scope Script -Name $objKey -Value $hashINIContent."$objKey"
	}
}

#convert ini string parameters into boolean values
Function Convert-StringToBool ($strInput) {
	$strInput = $strInput.Trim()

	#if an input string does not exist, return false
	If (-not $strInput) {
		Return $False
	}

	#try converting the string into a boolean value
	Try {
		$boolResult = [System.Convert]::ToBoolean($strInput)
	}
	Catch {
		Throw ("Invalid format: '{0}'. Use 'True' or 'False' only.")
	}

	Return $boolResult
}

#convert duration to sexagesimal format for display
Function Convert-ToSexagesimal ([ValidateRange(0.0, [float]::MaxValue)][float]$Duration) {
	
	[int]$intHours = [Math]::Truncate($Duration / 3600)
	[int]$intMins = [Math]::Truncate($Duration / 60) - ($intHours * 60)
	[float]$floatSecs = $Duration - ($intHours * 3600) - ($intMins * 60)
	
	$strHours = $intHours.ToString("00")
	$strMins = $intMins.ToString("00")
	$strSecs = $floatSecs.ToString("00.000")

	Return '{0}:{1}:{2}' -f $strHours, $strMins, $strSecs
}

Function Convert-FromSexagesimal ([ValidatePattern("^\d{2}\:\d{2}\:\d{2}\.\d+$")][string]$strDuration) {
	If (-not $strDuration) {
		Return [float]0.0
	}

	$arrDuration = $strDuration.Split(':')

	$intHours = [int]$arrDuration[0] * 60 * 60
	$intMins = [int]$arrDuration[1] * 60

	$arrSecsAndMils = $arrDuration[2].Split('.')

	$intSecs = [int]$arrSecsAndMils[0]
	$floatMils = [float]('0.' + $arrSecsAndMils[1])

	Return [float]($intHours + $intMins + $intSecs) + $floatMils
}

#round integers to arbitrary values
Function Round-Value ($floatInput, $intRound) {
	Return [System.Math]::Round($floatInput / $intRound) * $intRound
}

Function Set-CRF ($intCRF, $strVideoCodec) {
	If ($intCRF -ne -1) {
		Return $intCRF
	}

	#automatically set crf, depending on video codec, using sane default values
	If ($strVideoCodec -eq 'libx264') {
		Return 21
	}

	#otherwise, we assume it's libx265
	Return 19
}

#get the ini file path
#this function should only be used with tcs.ps1
Function Get-INIPath ($FilePath, $Rule) {
	#if we have a valid rule
	If ($Rule) {
		#construct the ini path
		$INIPath = '{0}\ini\{1}.ini' -f $PSScriptRoot, $Rule

		#if the ini path is valid, return it
		If (Test-Path -LiteralPath $INIPath) {
			Return $INIPath
		}

		#otherwise, the ini path is invalid, show a warning and return the default ini path
		Write-Warning ('Rule file: {0} for file: {1} does not exist. Using default.' -f $INIPath, $FilePath)
		Return $INIPathDefault
	}

	#otherwise, no rule is defined, show a warning and return the default ini path
	Write-Warning ('No rule defined for file: {0}. Using default.' -f $FilePath)
	Return $INIPathDefault
}

Function Get-PixelFormat ($objFFInfo, $objInputFile) {
	Return $objFFInfo.streams[$objInputFile.Index.Vid].pix_fmt
}

Function Set-OutputPixelFormat ($objInputFile, $strPixelFormat, $strVideoCodec) {
	If ($strPixelFormat -eq 'auto') {
		$strOutputFormat = $objInputFile.PixelFormat
	}
	Else {
		$strOutputFormat = $strPixelFormat
	}

	If (($strOutputFormat -ne 'yuv420p') -and ($strVideoCodec -eq 'libx264')) {
		Write-Warning ('Pixel format: {0} is poorly supported for codec: {1}. Forcing yuv420p.' -f $strOutputFormat, $strVideoCodec)
		$strOutputFormat = 'yuv420p'
	}

	Return $strOutputFormat
}

Function Show-Info ($objFFInfo) {
		$objStreamList = New-Object System.Collections.Generic.List[Object]

		$objFFInfo.streams | ForEach {
			If ($_.codec_type -ne 'attachment') {
				$objStream = [ordered]@{
					Index = $_.index
					CodecType = $_.codec_type
					CodecName = $_.codec_name
					FrameRate = ($_.r_frame_rate | Where-Object {$_ -ne '0/0'})
					Language = $_.tags.language
					Title = $_.tags.title
					Default = [Bool]$_.disposition.default
					Forced = [Bool]$_.disposition.forced
				}

				$objStreamList.Add($objStream)
			}
		}

		$objStreamList | ForEach {[PSCustomObject]$_} | Format-Table -AutoSize
}

Function Remove-TempFiles ($objTempFile) {
	#remove temporary directory
	$objTempFile.Directory | Remove-Item -ErrorAction SilentlyContinue -Force -Recurse

	#remove temporary files
	$objTempFile.MP4, $objTempFile.M4A, $objTempFile.FLAC, $objTempFile.ASS | Remove-Item -ErrorAction SilentlyContinue -Force
}

Function Check-Replace ($strReplace) {
	#return if the input string is empty
	If (-not $strReplace) {
		Return $Null
	}

	#check that the input string is a single array element
	If ($strReplace.Count -ne 1) {
		Throw ('Invalid format: String[] for replace: {0}. Use a single string only.' -f $strReplace)
	}

	#split the input by the pipe (|) character
	$arrReplace = $strReplace.Split('|')

	#check that the input does not contain empty elements
	If (($arrReplace | Where-Object {-not $_}).Count) {
		Throw ('Invalid value for replace: {0}. Empty element(s) found.' -f $strReplace)
	}

	#check that the input is not missing colon characters
	If (($arrReplace | Where-Object {$_ -notmatch ':'}).Count) {
		Throw ('Invalid value for replace: {0}. Missing colon(s).' -f $strReplace)
	}

	#check each element in the input string array
	$arrReplace | ForEach {
		$arrSplit = $_.Split(':')

		#check that we only have two elements per split
		#this implies only one colon per array elemnent, and allows for
		#empty elements
		If ($arrSplit.Count -ne 2) {
			Throw ('Invalid value for replace: {0}. Too many colons.' -f $strReplace)
		}

		#check that the first string in the element is not empty
		If (-not $arrSplit[0]) {
			Throw ('Invalid value for replace: {0}. Cannot replace an empty string.' -f $strReplace)
		}
	}

	Return $arrReplace
}

Function Check-FrameRate ($FrameRate, $boolIsInput) {
	$strFrameRate = [string]$FrameRate.ToLower().Trim()
	
	#if the frame rate is set to auto
	If (($strFrameRate -eq 'auto') -or [string]::IsNullOrEmpty($strFrameRate)) {
		Return 'auto'
	}
	
	#do not allow vfr for input frame rate
	If ($boolIsInput -and ($strFrameRate -eq 'vfr')) {
		Throw ("Cannot use variable frame rate for input: ($strFrameRate).")
	}
	
	If ($strFrameRate -eq 'vfr') {
		Return 'vfr'
	}
	
	#otherwise, get the frame rate
	#define min and max frame rate values
	$decFrameRateMin = 0.001
	$decFrameRateMax = 1200.0
	
	#check for a valid fraction
	#make sure we have a numerator and denominator
	$arrFrameRate = $strFrameRate.Split('/')
	If ($arrFrameRate.Count -eq 2) {
		Try {
			$decNumerator = [decimal]$arrFrameRate[0]
			$decDenominator = [decimal]$arrFrameRate[1]
		}
		Catch {
			Throw ("Invalid fractional value for frame rate: ($strFrameRate).")
		}
		
		Return $strFrameRate
	}
	#otherwise, we do not have a valid fraction
	Else {
		#try converting to a decimal value
		Try {
			$decFrameRate = [decimal]$strFrameRate
		}
		Catch {
			Throw ("Invalid decimal value for frame rate: ($strFrameRate.)")
		}
		
		#if the frame rate is less than or equal to min or greater than max
		If (($decFrameRate -le $decFrameRateMin) -or ($decFrameRate -gt $decFrameRateMax)) {
			#it is invalid
			Throw ("Invalid decimal value for frame rate: ($strFrameRate). Please use a value between $decFrameRateMin and $decFrameRateMax.")
		}
		
		Return $strFrameRate
	}
}

Function Check-Path ($strInputPath) {
	If (-not (Test-Path -IsValid $strInputPath)) {
		Throw('Path: {0} Is invalid. Please choose a different path.' -f $strInputPath)
	}

	#258 characters, as output file needs to have at least 1 character and we need to include backslash
	If ((Split-Path $strInputPath).Length -gt 258) {
		Throw("Path: {0} Exceeds maximum character limit. Please choose a different path." -f $strInputPath)
	}

	Return [string]($strInputPath).TrimEnd('\')
}

#determines if the subs parameter should be enabled / disabled
#this function must be called before any language parameter checking occurs
Function Check-Subs ($Subs, $SubIndex, $SubTitle, $SubLang) {
	#if subtitles are enabled or subindex is defined or subtitle is defined or sublang is defined, return true
	If (($Subs) -or ([int]$SubIndex -ne -1) -or ($SubTitle) -or ($SubLang)) {
		Return $True
	}

	#otherwise, return false
	Return $False
}

#determines if the scrape parameter should be enabled / disabled
#this function must be called before any language parameter checking occurs
Function Check-Scrape ($Scrape, $ShowQuery, $ScrapeLang, $SeasonQuery, $EpisodeQuery, $SeriesID) {
	#if scrape is enabled or any query is valid or scrapelang is defined or seriesid is defined or episode offset is defined, return true
	If (($Scrape) -or ($ShowQuery)  -or ($ScrapeLang) -or ([int]$SeasonQuery -ne -1) -or ([int]$EpisodeQuery -ne -1) -or ([int]$SeriesID -ne -1)) {
		Return $True
	}

	#otherwise, return false
	Return $False
}

#check that the video preset parameter is valid
Function Check-VideoPreset($VideoPreset) {
	#valid presets
	$arrVideoPresets = @('ultrafast', 'superfast', 'veryfast', 'faster', 'fast', 'medium', 'slow', 'slower', 'veryslow', 'placebo')

	#if the preset is valid, use it
	If ($arrVideoPresets -contains $VideoPreset.ToLower()) {
		Return $VideoPreset
	}

	#otherwise throw an error
	Throw ('Invalid preset, valid presets: {0}.' -f ($arrVideoPresets -join ', '))
}

#check that the input language parameter is valid
Function Check-Lang ($InputLang) {
	#if the language is undefined, return system language
	If (-not $InputLang)  {
		Return (Get-Culture).ThreeLetterISOLanguageName
	}

	#initialize an array with all valid (iso 639-2) language codes
	$arrLangCodes = @(`
	'aar','abk','ace','ach','ada','ady','afa','afh','afr','ain','aka','akk','alb','ale','alg','alt','amh','ang',`
	'anp','apa','ara','arc','arg','arm','arn','arp','art','arw','asm','ast','ath','aus','ava','ave','awa','aym',`
	'aze','bad','bai','bak','bal','bam','ban','baq','bas','bat','bej','bel','bem','ben','ber','bho','bih','bik',`
	'bin','bis','bla','bnt','bos','bra','bre','btk','bua','bug','bul','bur','byn','cad','cai','car','cat','cau',`
	'ceb','cel','cha','chb','che','chg','chi','chk','chm','chn','cho','chp','chr','chu','chv','chy','cmc','cop',`
	'cor','cos','cpe','cpf','cpp','cre','crh','crp','csb','cus','cze','dak','dan','dar','day','del','den','dgr',`
	'din','div','doi','dra','dsb','dua','dum','dut','dyu','dzo','efi','egy','eka','elx','eng','enm','epo','est',`
	'ewe','ewo','fan','fao','fat','fij','fil','fin','fiu','fon','fre','frm','fro','frr','frs','fry','ful','fur',`
	'gaa','gay','gba','gem','geo','ger','gez','gil','gla','gle','glg','glv','gmh','goh','gon','gor','got','grb',`
	'grc','gre','grn','gsw','guj','gwi','hai','hat','hau','haw','heb','her','hil','him','hin','hit','hmn','hmo',`
	'hrv','hsb','hun','hup','iba','ibo','ice','ido','iii','ijo','iku','ile','ilo','ina','inc','ind','ine','inh',`
	'ipk','ira','iro','ita','jav','jbo','jpn','jpr','jrb','kaa','kab','kac','kal','kam','kan','kar','kas','kau',`
	'kaw','kaz','kbd','kha','khi','khm','kho','kik','kin','kir','kmb','kok','kom','kon','kor','kos','kpe','krc',`
	'krl','kro','kru','kua','kum','kur','kut','lad','lah','lam','lao','lat','lav','lez','lim','lin','lit','lol',`
	'loz','ltz','lua','lub','lug','lui','lun','luo','lus','mac','mad','mag','mah','mai','mak','mal','man','mao',`
	'map','mar','mas','may','mdf','mdr','men','mga','mic','min','mis','mkh','mlg','mlt','mnc','mni','mno','moh',`
	'mon','mos','mul','mun','mus','mwl','mwr','myn','myv','nah','nai','nap','nau','nav','nbl','nde','ndo','nds',`
	'nep','new','nia','nic','niu','nno','nob','nog','non','nor','nqo','nso','nub','nwc','nya','nym','nyn','nyo',`
	'nzi','oci','oji','ori','orm','osa','oss','ota','oto','paa','pag','pal','pam','pan','pap','pau','peo','per',`
	'phi','phn','pli','pol','pon','por','pra','pro','pus','qaa','que','raj','rap','rar','roa','roh','rom','rum',`
	'run','rup','rus','sad','sag','sah','sai','sal','sam','san','sas','sat','scn','sco','sel','sem','sga','sgn',`
	'shn','sid','sin','sio','sit','sla','slo','slv','sma','sme','smi','smj','smn','smo','sms','sna','snd','snk',`
	'sog','som','son','sot','spa','srd','srn','srp','srr','ssa','ssw','suk','sun','sus','sux','swa','swe','syc',`
	'syr','tah','tai','tam','tat','tel','tem','ter','tet','tgk','tgl','tha','tib','tig','tir','tiv','tkl','tlh',`
	'tli','tmh','tog','ton','tpi','tsi','tsn','tso','tuk','tum','tup','tur','tut','tvl','twi','tyv','udm','uga',`
	'uig','ukr','umb','und','urd','uzb','vai','ven','vie','vol','vot','wak','wal','war','was','wel','wen','wln',`
	'wol','xal','xho','yao','yap','yid','yor','ypk','zap','zbl','zen','zgh','zha','znd','zul','zun','zxx','zza')

	#make sure the input language is in the correct format for matching
	$InputLang = ($InputLang.ToLower()).Trim()

	#if the input language is in $arrlangcodes, return it
	If ($arrLangCodes -contains $InputLang) {
		Return $InputLang
	}

	#otherwise the input language is invalid, throw an error
	Throw ('{0} is not valid. Please use ISO 639-2 language codes only: https://en.wikipedia.org/wiki/List_of_ISO_639-2_codes' -f $InputLang)
}

Function Get-StringHash ($strInput, $intLength) {
	$stringAsStream = [System.IO.MemoryStream]::new()
	$writer = [System.IO.StreamWriter]::new($stringAsStream)
	$writer.write($strInput)
	$writer.Flush()
	$stringAsStream.Position = 0
	$strOutput = Get-FileHash -InputStream $stringAsStream | Select-Object Hash
	
	Return ($strOutput.Hash).SubString(0, $intLength - 1)
}

Function Set-FrameRateOpts ($objFrameRateIn, $objFrameRateOut, $FrameRateIn) {
	#construct a new frame rate option object
	$objFrameRateOpts = [FrameRateOpts]::New()
	
	If ($FrameRateIn -ne 'auto') {
		$objFrameRateOpts.InOpt = '-r'
		$objFrameRateOpts.InVal = $objFrameRateIn.Fraction
	}
	
	If ($objFrameRateOut.Mode -eq 'vfr') {
		$objFrameRateOpts.OutOpt = '-fps_mode'
		$objFrameRateOpts.OutVal = 'vfr'
	}
	Else {
		$objFrameRateOpts.OutOpt = '-r'
		$objFrameRateOpts.OutVal = $objFrameRateOut.Fraction
	}
	
	Return $objFrameRateOpts
}