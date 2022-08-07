#Construct Info Object
Function Construct-InfoObject {
	$objInfo = [PSCustomObject]@{
			Input = @{
				FullName = ''
				BaseName = ''
				Extension = ''
				Duration = @{
					AsFloat = 0.0
					AsString = ''
					IsMetadata = $False
				}
				FrameCount = @{
					AsInt = 0
					IsMetadata = $False
				}
				FrameRate = @{
					AsFloat = 0
					AsString = ''
				}
				Resolution = @{
					Width = 0
					Height = 0
				}
			}
			Output = @{
				FullName = ''
				BaseNameClean = ''
				Extension = ''
				Random = @{
					BaseName = ''
					FLAC = ''
					MP4 = ''
					M4A = ''
				}
				FrameRate = @{
					AsFloat = 0.0
					AsString = ''
				}
			}
			Scrape = @{
				ShowTitle = ''
				EpisodeTitle = ''
				Season = ''
				Episode = ''
			}
			Index = @{
				Video = 0
				Audio = 0
				Sub = 0
			}
			Filter = @{
				Crop = ''
				Scale = ''
				Subs = ''
				Chain = ''
			}
		}
		
		Return $objInfo
}

#Get Video Index From Input File Info Object
Function Get-VideoIndex ($objFFInfo, $VideoIndex) {
	#Get A List Of Video Streams
	$objVideoStreams = $objFFInfo.streams | Where-Object {($_.codec_type -eq 'video') -and ($_.disposition.attached_pic -ne 1)}
	
	#No Video Streams
	If (!$objVideoStreams) {
		Return -1
	}
	
	#Use Manually Defined Video Index
	If ($VideoIndex -ne -1) {
		$intVideoIndex = ($objVideoStreams | Where-Object {$_.index -eq $VideoIndex}).index
		If ($intVideoIndex -ne $null) {
			Return $intVideoIndex
		}
	}
	
	#Use Container Default Video Stream
	$intDefaultIndex = ($objVideoStreams | Where-Object {$_.disposition.default -eq 1}).index | Select-Object -First 1
	If ($intDefaultIndex -ne $null) {
		Return $intDefaultIndex
	}
	
	#Use First Highest Resolution Stream
	$intHighestRes = 0
	$objVideoStreams | % {
		$intStreamRes = $_.width * $_.height
		If ($intStreamRes -gt $intHighestRes) {
			$intHighestRes = $intStreamRes
			$intResIndex = $_.index
		}
	}
	
	Return $intResIndex
}

#Get Subtitle Index From Input File Info Object
Function Get-SubIndex ($objFFInfo, $objInfo, $SubIndex, $SubLang, $SubTitle, $Subs) {
	#Subtitles Disabled
	If (!$Subs) {
		Return -1
	}
	
	#Get A List Of Subtitle Streams
	$objSubStreams = $objFFInfo.streams | Where-Object {$_.codec_type -eq 'subtitle'}
	
	#No Subtitle Streams
	If ($objSubStreams -eq $null) {
		Return -1
	}
	
	#If The Subtitle Index Is Manually Defined
	If ($SubIndex -ne -1) {
		$intSubIndex = ($objSubStreams | Where-Object {$_.index -eq $SubIndex}).index
		If ($intSubIndex -ne $null) {
			Return $intSubIndex
		}
	}
	
	#Use Subtitle Title
	If ($SubTitle) {
		$intTitleIndex = ($objSubStreams | Where-Object {$_.tags.title -eq $SubTitle}).index | Select-Object -First 1
		If ($intTitleIndex -ne $null) {
			Return $intTitleIndex
		}
	}
	
	#Use Subtitle Language
	If ($SubLang -ne $null) {
		$intLangIndex = ($objSubStreams | Where-Object {$_.tags.language -eq $SubLang}).index | Select-Object -First 1
		If ($intLangIndex -ne $null) {
			Return $intLangIndex
		}
	}
	
	#Use Container Default Subtitle Stream
	$intDefaultIndex = ($objSubStreams | Where-Object {$_.disposition.default -eq 1}).index | Select-Object -First 1
	If ($intDefaultIndex -ne $null) {
		Return $intDefaultIndex
	}
	
	#Use Any Subtitle Stream
	$intAnyIndex = ($objSubStreams | Select-Object -First 1).index
	If ($intAnyIndex -ne $null) {
		Return $intAnyIndex
	}
}

#Get Audio Index From Input File Info Object
Function Get-AudioIndex ($objFFinfo, $objInfo, $AudioIndex, $AudioLang, $AudioTitle, $NoAudio) {
	#Audio Disabled
	If ($NoAudio) {
		Return -1
	}
	
	#Get A List Of Audio Streams
	$objAudioStreams = $objFFInfo.streams | Where-Object {$_.codec_type -eq 'audio'}
	
	#No Audio Streams
	If ($objAudioStreams -eq $null) {
		Return -1
	}
	
	#Use Manually Defined Audio Index
	If ($AudioIndex -ne -1) {
		$intAudioIndex = ($objAudioStreams | Where-Object {$_.index -eq $AudioIndex}).index
		If ($intAudioIndex -ne $null) {
			Return $intAudioIndex
		}
	}
	
	#Use Audio Title
	If ($AudioTitle) {
		$intTitleIndex = ($objAudioStreams | Where-Object {$_.tags.title -eq $AudioTitle}).index | Select-Object -First 1
		If ($intTitleIndex -ne $null) {
			Return $intTitleIndex
		}
	}
	
	#Use Audio Language
	If ($AudioLang -ne $null) {
		$intLangIndex = ($objAudioStreams | Where-Object {$_.tags.language -eq $AudioLang}).index | Select-Object -First 1
		If ($intLangIndex -ne $null) {
			Return $intLangIndex
		}
	}
	
	#Use Container Default Audio Stream
	$intDefaultIndex = ($objAudioStreams | Where-Object {$_.disposition.default -eq 1}).index | Select-Object -First 1
	If ($intDefaultIndex -ne $null) {
		Return $intDefaultIndex
	}
	
	#Use Any Audio Stream
	$AudioIndex = ($objAudioStreams | Select-Object -First 1).index
	If ($AudioIndex -ne $null) {
		Return $AudioIndex
	}
}

#Set Cropping Values For Chosen Video Stream
Function Set-Crop ($objInfo, $ForceCrop, $NoCrop, $MinRes) {
	#No Cropping
	If ($NoCrop) {
		Return $null
	}
	
	#Initialize Input Width And Height
	$intInputWidth = $objInfo.Input.Resolution.Width
	$intInputHeight = $objInfo.Input.Resolution.Height
		
	#Check If Forced Crop Is Enabled And Valid
	If ($ForceCrop) {
		#Get Crop Values
		$arrForceCrop = $ForceCrop.Split(':')
		$intTotalWidth = $arrForceCrop[0] + $arrForceCrop[2]
		$intTotalHeight = $arrForceCrop[1] + $arrForceCrop[3]

		#If Forced Crop Is Within Width / Height Bounds, Use That
		If (($intTotalWidth -le $intInputWidth) -and ($intTotalHeight -le $intInputHeight) -and ($intTotalWidth -ge $MinRes.Split(':'[0])) -and ($intTotalHeight -ge $MinRes.Split(':'[1]))) {
			Return 'crop=' + $ForceCrop
		}
		#Otherwise, Show A Warning, Then Run Auto Crop Anyway
		Else {
			Write-Warning ("Forced crop '$ForceCrop' is out of bounds, using auto-crop.")
		}
	}
	
	#Start Auto Cropping
	$objCropList = New-Object System.Collections.Generic.List[String]
	$intTotalIterations = 10
	$intFrameAmt = 30
	$intCropConfidence = 50
	
	#Ensure Video Is Long Enough To Perform Auto-Crop
	If (($objInfo.Input.FrameRate.AsFloat * $objInfo.Input.Duration.AsFloat) -lt ($intFrameAmt * $intTotalIterations)) {
		Write-Warning ("Video duration is too short (" + $objInfo.Input.Duration.AsString + "). Bypassing auto-crop.")
	}

	$intSeekChunk = [int]($objInfo.Input.Duration.AsFloat / $intTotalIterations)
	
	#Run Auto Crop
	$intCropCounter = 0
	While ($intCropCounter -lt $intTotalIterations) {
		$intSeekSeconds =  [int]($intCropCounter * $intSeekChunk)
		
		#Run FFmpeg
		$strCropDetect = .\bin\ffmpeg.exe -ss $intSeekSeconds -i $objInfo.Input.FullName -map ('0:' + $objInfo.Index.Video) -frames $intFrameAmt -vf cropdetect=24:4 -f null nul 2>&1
		
		#Split Ffmpeg Output String To Get Crop Parameters
		$strCrop = [regex]::Split([regex]::Split($strCropDetect, 'crop=')[-1], "`r`n")[0].Trim()
		$strCrop = $strCrop.Split("frame=")[0].Trim()
		
		#Add Current Crop Value To Crop List
		$objCropList.Add($strCrop)
		
		#Calculate / Format Progress Percentage
		$floatProgress = (([Int]$intCropCounter / [Int]($intTotalIterations - 1)) * 100).ToString("0.0")
		
		#Display Progress
		$strProgress = "`rAuto-cropping [$floatProgress%]"
		Write-Host $strProgress -NoNewLine
		
		#Remove The Carriage Return From The Beginning Of The Progress String
		$strProgress = $strProgress -replace '\r',''
		
		$intCropCounter++
	}
		
	Write-Host ("`r" + ' ' * $strProgress.Length + "`r") -NoNewLine
	
	#Make Sure Cropping Confidence Is Greater Than 50%
	#Get The Most Common Cropping Value
	$objCrop = $objCropList | Group-Object | Sort-Object Count -Descending | Select-Object -First 1
	[float]$floatCropConfidence = ($objCrop.Count / $intTotalIterations) * 100
	
	#Bypass Crop If Not Confident
	If ($floatCropConfidence -lt $intCropConfidence) {
		Write-Warning ("Auto-crop confidence is below $intCropConfidence% (" + ("{0:n1}" -f $floatCropConfidence) + "%). No cropping applied.")
		
		Return $Null
	}
	
	#Get The Most Common Auto-Crop String
	$strCrop = $objCrop | Select-Object -ExpandProperty Name -First 1
	
	#If Height / Width Has Not Changed, Do Nothing
	$arrCrop = $strCrop.Split(':')
	
	If (($intInputWidth -eq $arrCrop[0]) -and ($intInputHeight -eq $arrCrop[1])) {
		Return $Null
	}
	
	Return ('crop=' + $strCrop)
}

#Sets Scaling For Chosen Video Stream
Function Set-Scale ($objInfo, $Round, $ForceRes, $MinRes, $MaxRes) {
	#Get The Minimum Allowed Resolution
	$arrMinRes = $MinRes.ToLower().Split('x')
	
	#If Forced Resolution Is Defined
	If ($ForceRes) {
		#If The Forced Resolution Is Outside Of The Minimum Width / Height, Skip Scaling
		$arrForceRes = $ForceRes.ToLower().Split('x')
		
		If (([Int]$arrForceRes[0] -lt [Int]$arrMinRes[0]) -or ([Int]$arrForceRes[1] -lt [Int]$arrMinRes[1])) {
			Write-Warning ("Forced resolution: '" +  $ForceRes + "', is smaller than the allowed minimum: '" + $MinRes + "', skipping scaling.")
			Return $null
		}
		
		Return 'scale=' + $arrForceRes[0] + ':' + $arrForceRes[1] + ',setsar=1'
	}
	
	#Next, Check If There Is Any Cropping, And Use Those Values For The Input Width / Height
	If ($objInfo.Filter.Crop -ne $null) {
		$arrCrop = ($objInfo.Filter.Crop.Split('='))[-1].Split(':')
		$intInputWidth = [Int]$arrCrop[0]
		$intInputHeight = [Int]$arrCrop[1]
	}
	#Otherwise, Get The Original Resolution And Use Those Values For The Input Width / Height
	Else {
		$intInputWidth = $objInfo.Input.Resolution.Width
		$intInputHeight = $objInfo.Input.Resolution.Height
	}
	
	#Get Maximum Width / Height
	$arrMaxRes = $MaxRes.Split('x')
	$intMaxWidth = [Int]$arrMaxRes[0]
	$intMaxHeight = [Int]$arrMaxRes[1]
	
	#Next, Get Scaled Width / Height
	#Check If Input Width Is Greater Than Maximum Width
	If ($intInputWidth -gt $intMaxWidth) {
		#Set Input Width To Maximum Width
		$intOutputWidth = $intMaxWidth
		
		#Calculate Max Height Based On Maximum Width
		$intOutputHeight = ($intMaxWidth / $intInputWidth) * $intInputHeight
		
		#If Output Height Is Greater Than Maximum Height
		#Scale Output Width Based On Maximum Height
		#This Way, We Are Always Within The Limits Of The Maximum Resolution
		If ($intOutputHeight -gt $intMaxHeight) {
			$intOutputWidth = ($intMaxHeight / $intOutputHeight) * $intOutputWidth
			$intOutputHeight = $intMaxHeight
		}
	}
	#Otherwise, If Input Height Is Greater Than Maximum Height
	#Scale Output Width Based On Maximum Height
	ElseIf ($intInputHeight -gt $intMaxHeight) {
		$intOutputHeight = $intMaxHeight
		$intOutputWidth = ($intMaxHeight / $intInputHeight) * $intInputWidth
	}
	#Otherwise, We Are Within Max Width / Height Limits
	#Set Output Width / Height As Input Width / Height
	Else {
		$intOutputWidth = $intInputWidth
		$intOutputHeight = $intInputHeight
	}
	
	#Round Max Width / Height
	[Int]$intOutputWidth = Round-Value $intOutputWidth $Round
	[Int]$intOutputHeight = Round-Value $intOutputHeight $Round
	
	#1080p Rounding Hack
	If (($intOutputHeight -eq 1088) -or ($intOutputHeight -eq 1072)) {
		$intOutputHeight = 1080
	}
	
	#Do Nothing If Input Width / Height Is Equal To Output Width / Height
	If (($intInputHeight -eq $intOutputHeight) -and ($intInputWidth -eq $intOutputWidth)) {
		Return $null
	}
	
	#Skip Scaling If Scaled Width / Height Is Less Than Minimum Width / Height
	If (($intOutputWidth -lt $arrMinRes[0]) -or ($intOutputHeight -lt $arrMinRes[1])) {
		Write-Warning ("Scaled resolution: '" + $intOutputWidth + 'x' + $intOutputHeight + "', is smaller than the allowed minimum: '" + $MinRes + "', skipping scaling.")
		Return $null
	}
	
	#Set The Scaling Algorithm To Bilinear If Downscaling
	If (($intInputWidth * $intInputHeight) -gt ($intOutputWidth * $intOutputHeight)) {
		$strScaleAlgo = ':sws_flags=bilinear'
	}
	
	#Construct The Scaling Filter String
	Return 'scale=' + $intOutputWidth + ':' + $intOutputHeight + $strScaleAlgo
}

#Set Up The Subtitle Filter String
Function Set-Subs ($objFFInfo, $objInfo, $ForceRes, $Subs) {
	#Return Null If No Subs Found Or Subs Disabled
	If ($objInfo.Index.Sub -eq -1) {
		Return $null
	}
		
	#Set Up The Filter If Subtitles Are PGS
	$objSubStream = $objFFInfo.streams | Where-Object {$_.index -eq $objInfo.Index.Sub}
	If (($objSubStream.codec_name -eq 'hdmv_pgs_subtitle') -or ($objSubStream.codec_name -eq 'dvd_subtitle')) {
		Return '[0:' + $objInfo.Index.Sub + ']overlay'
	}
	
	#Otherwise Enumerate All Non PGS Subtitles So The 'Subtitle' Filter
	$intSubFilterIndex = 0
	$objFFInfo.streams | Where-Object {$_.codec_type -eq 'subtitle'} | % {
		If (($_.codec_name -ne 'hdmv_pgs_subtitle') -and ($_.codec_name -ne 'dvd_subtitle')) {
			If ($_.index -eq $objInfo.Index.Sub) {
				#If Resolution Is Forced, We Have To Maintain Original Aspect Ratio
				If ($ForceRes) {
					$strSubForceRes = ':original_size=' + $objInfo.Input.Resolution.Width + 'x' + $objInfo.Input.Resolution.Height
				}
				
				Return 'subtitles=' + `
				'filename="' + (Escape-Filter $objInfo.Input.FullName) + '"' + `
				':fontsdir="' + (Escape-Filter ($PSScriptRoot + '\' + $objInfo.Output.Random.BaseName)) + '"' + `
				':si=' + $intSubFilterIndex + $strSubForceRes
			}
			$intSubFilterIndex++
		}
	}
}

Function Normalize-Name ($strInput) {
	#Replace '–|—|−' With '-'
	$strInput = $strInput -replace '–|—|−', '-'
	
	#Replace '’' With '''
	$strInput = $strInput -replace "’", "'"
	
	#Replace '`'  With '''
	$strInput = $strInput -replace "``", "'"
	
	#Replace ':' With '-'
	$strInput = $strInput -replace ':', '-'
	
	#Replace '?' With '-' (This causes issues with mp4box)
	$strInput = $strInput -replace [regex]::Escape('?'), '-'
	
	#Remove Any Accented Characters
	[char[]]$strInput.Normalize('FormD') | % {
		If ([System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($_) -ne 'NonSpacingMark') {
			$strNoAccents = $strNoAccents + $_
		}
	}
	$strInput = $strNoAccents
	
	#Replace Invalid File System Characters With '-'
	$strInvalidChars = [IO.Path]::GetInvalidFileNameChars() -join ''
	$strInput = $strInput -replace [regex]::Escape($strInvalidChars), '-'
	
	#Trim Whitespace From Either End Of The Input String
	$strInput = $strInput.Trim()
	
	#Convert Multiple Spaces To Single Spaces
	$strInput = $strInput -replace '\s+', ' '
	
	Return $strInput
}

#Clean Up The Input Name
Function Clean-Name ($strInput, $Replace) {
	#Process Any String Replacements
	If ($Replace) {
		$Replace | % {
			$arrStringReplace = $_.Split(':')
			If ($arrStringReplace[0]) {
				$strReplaceIn = $arrStringReplace[0]
			}
			
			If ($arrStringReplace[1]) {
				$strReplaceOut = $arrStringReplace[1]
			}
			
			$strInput = $strInput -ireplace [regex]::Escape($strReplaceIn), [regex]::Escape($strReplaceOut)
		}
	}
	
	#Clean And Instances Of The Regex Escape Character ('\')
	#There Is No Chance Of Any Being Left Over
	#As This Would Result In An Invalid File Name
	$strInput = $strInput.Replace('\', '')
	
	#Clean Between '[' And ']'
	$strInput = $strInput -replace '\[.*?\](?![^\[\]]*\])', ''

	#Clean Between '(' And ')'
	$strInput = $strInput -replace '\(.*?\)(?![^\(\)]*\))', ''
	
	#Replace '.' With ' '
	$strInput = $strInput.Replace('.', ' ')

	#Replace '_' With ' '
	$strInput = $strInput.Replace('_', ' ')
	
	#Normalize Name
	$strInput = Normalize-Name $strInput
	
	#Make The Sxxexx String The Correct Format
	If ($strInput -match ' (s|S)\d{1,2}(e|E)\d{1,2}( |$)') {
		$strInput = $strInput.Replace($Matches[0], $Matches[0].ToUpper())
	}
	
	Return $strInput
}

#Get The Full Output Name Path
Function Get-OutputPath ($objInfo, $OutputPath, $Scrape, $ScrapeLang, $CleanName, $EpisodeOffset, $SeriesID, $Digits) {
	#Get All Required Info, Fills Out ObjInfo With Needed Data
	Get-NameInfo $objInfo $Scrape $ScrapeLang $EpisodeOffset $SeriesID
	
	#If Scraping Was Enabled
	If ($Scrape) {
		#If All Info Is Available, Build The Full Output Name
		$strShowTitle = $objInfo.Scrape.ShowTitle
		$strEpisodeTitle = $objInfo.Scrape.EpisodeTitle
		$intSeason = [int]$objInfo.Scrape.Season
		$intEpisode = [int]$objInfo.Scrape.Episode
		
		If (($strShowTitle) -and ($intSeason -gt -1) -and ($objInfo.Scrape.Episode -gt -1) -and ($strEpisodeTitle)) {
			$strEpisodeNumber = $intEpisode.ToString($Digits)
			$strSeasonNumber = $intSeason.ToString($Digits)
			
			$strOutputPath = $OutputPath + '\' + $strShowTitle + '\Season ' + $strSeasonNumber + '\' + $strShowTitle + ' S' + $strSeasonNumber + 'E' + $strEpisodeNumber + ' - ' + $strEpisodeTitle + $objInfo.Output.Extension
			
			Return $strOutputPath
		}
	}
	
	#If Clean Name Is Enabled, Use The Cleaned Name Only
	If (($CleanName) -and ($objInfo.Output.BaseNameClean)) {
		
		$strOutputPath = $OutputPath + '\' + $objInfo.Output.BaseNameClean + $objInfo.Output.Extension
		
		Return $strOutputPath
	}
		
	#Otherwise, Use The Input Name
	$strOutputPath = $OutputPath + '\' + $objInfo.Input.BaseName + $objInfo.Output.Extension
	
	Return $strOutputPath
}

Function Check-Path ($strInputPath) {
	If (!(Test-Path -IsValid $strInputPath)) {
		Throw("Path '" + $strInputPath + "' Is invalid. Please choose a different path.")
	}
	
	#258 Characters, As Output File Needs To Have At Least 1 Character And We Need To Include Backslash
	If ((Split-Path $strInputPath).Length -gt 258) {
		Throw("Path '" + $strInputPath + "' Exceeds maximum character limit. Please choose a different path.")
	}
	
	Return [string]($strInputPath).TrimEnd('\')
}

#Get Info For Making Full Output Name
Function Get-NameInfo ($objInfo, $Scrape, $ScrapeLang, $EpisodeOffset, $SeriesID) {
	#Use ' SxxExxx' Regex Pattern To Get Season And Episode Numbers
	If ($objInfo.Output.BaseNameClean -match ' S\d{1,2}E\d{1,3}( |$)') {
		#Get Season And Episode Number String
		$strSeasonEp = ($Matches[0]).Trim().ToUpper()
		
		#If No Show Query, Get The Show Title
		If (!$objInfo.Scrape.ShowTitle) {
			$objInfo.Scrape.ShowTitle = (($objInfo.Output.BaseNameClean -split $strSeasonEp)[0]).Trim()
		}
		
		#If No Season Query, Get The Season Number
		If ([Int]$objInfo.Scrape.Season -le -1) {
			$objInfo.Scrape.Season = ((($strSeasonEp.Split('E'))[0]).TrimStart('S'))
		}
		
		#If No Episode Query, Get The Episode Number
		If ([Int]$objInfo.Scrape.Episode -le -1) {
			$objInfo.Scrape.Episode = [Int](($strSeasonEp.Split('E'))[1]) + $EpisodeOffset
		}
	}
	#Otherwise There Was No Info Matched From BaseNameCleaned
	Else {
		#If Scraping Was Enabled And No Season Number And Episode Number Is Defined, Show A Warning
		If (($Scrape) -and ([Int]$objInfo.Scrape.Season -le -1) -and ([Int]$ObjInfo.Scrape.Episode -le -1)) {
			Write-Warning ("Could not match cleaned input name '" + $objInfo.Output.BaseNameClean + "' for scraping. Try to match the format: 'Show Title S01E01'")
		}
	}
	
	#Only Scrape If Scrape Is Enabled, And Show / Season / Episode Are All Defined
	If ($Scrape) {
		If (($objInfo.Scrape.ShowTitle) -and ([Int]$objInfo.Scrape.Season -gt -1) -and ([Int]$objInfo.Scrape.Episode -gt -1)) {
			$objInfo.Scrape.EpisodeTitle = Scrape-EpisodeTitle $objInfo $ScrapeLang $SeriesID
		}
	}
}

#Scrape The Episode Title
Function Scrape-EpisodeTitle ($objInfo, $ScrapeLang, $SeriesID) {
	#Set The TVDB Database Query Variables, These Are Needed To Use The API Correctly
	$strAPIKey = '6262A88CCAB7E724'
	$strEpOrder = 'default'

	#If We Have A Manually Defined Series ID, Use That
	If ($SeriesID -ne -1) {
		$strSeriesID = $SeriesID
	}
	#Otherwise Try To Scrape It From Show Title
	Else {
		#First, Query The Series Name To Get The Series XML Object
		$strURL = 'http://thetvdb.com/api/GetSeries.php?seriesname=' + ([uri]::EscapeDataString($objInfo.Scrape.ShowTitle))
		
		#Try To Scrape
		Try {
			$ProgressPreference = 'SilentlyContinue'
			$xmlInfo = $null
			[xml]$xmlInfo = Invoke-RestMethod $strURL -ErrorAction SilentlyContinue
			$ProgressPreference = 'Continue'
		}
		#Show Warning If Scrape Failed
		Catch {
			Write-Warning "Web request for data scrape failed."
			Return $null
		}
		
		#Return Null / Show A Warning If No Series ID Was Retrieved
		#An Empty String Comparison Works Consistently Here
		If ($xmlInfo.Data -eq '') {
			Write-Warning ("No show title scrape data found for: " + $objInfo.Output.ShowTitle)
			Return $null
		}
		
		#Always Get The First Series ID Match In The Returned XML Query For The Show Title
		If (($xmlInfo.data.series.seriesid).Count -gt 1) {
			$strSeriesID = $xmlInfo.data.series.seriesid[0]
		}
		Else {
			$strSeriesID = $xmlInfo.data.series.seriesid
		}
	}
	
	#Construct The Scrape URL
	$strURL = 'http://www.thetvdb.com/api/' + $strAPIKey + '/series/' + $strSeriesID + '/' + $strEpOrder + '/' + $objInfo.Scrape.Season + '/' + $objInfo.Scrape.Episode + '/' + $ScrapeLang
	
	#Try Running The Web Request
	Try {
		$ProgressPreference = 'SilentlyContinue'
		[xml]$xmlInfo = Invoke-RestMethod $strURL -ErrorAction SilentlyContinue
		$ProgressPreference = 'Continue'
	}
	#Show A Warning If Scrape Failed
	Catch {
		Write-Warning "Web request for data scrape failed."
		Return $null
	}
	
	#Return Null / Show A Warning If No Episode Info Was Scraped
	If ($xmlInfo.Data.Episode.id -eq 0) {
		Write-Warning ("No episode title scrape data found for: '" + $objInfo.Scrape.ShowTitle + "'")
		Return $null
	}

	#Set The Episode Title From Scraped Data
	$strEpisodeTitle = $xmlInfo.Data.Episode.EpisodeName
	
	#Normalize Name
	$strEpisodeTitle = Normalize-Name $strEpisodeTitle

	Return $strEpisodeTitle
}

#Round Integers To Arbitrary Values
Function Round-Value ($floatInput, $intRound) {
	Return [System.Math]::Round($floatInput / $intRound) * $intRound
}

#Build Video Filter Chain
Function Build-Filter ($objInfo) {
	#Make Sure The String Starts As Null
	$strFilterChain = $null

	#If We Have Picture Based (PGS) Subtitles Exist, We Need To Set Up A Second Filterchain
	$objSubStream = $objFFInfo.streams | Where-Object {$_.index -eq $objInfo.Index.Sub}
	If (($objSubStream.codec_name -eq 'hdmv_pgs_subtitle') -or ($objSubStream.codec_name -eq 'dvd_subtitle')) {
		#If We Have Scaling, Scale PGS Subtitles Using The Same Resolution As The Scale Filter
		If ($objInfo.Filter.Scale) {
			$arrScale = ($objInfo.Filter.Scale.Split('=')[1]).Split(':')
			$strScaleWidth = $arrScale[0]
			$strScaleHeight = $arrScale[1]
			
			$strSubChain = ';[0:' + $objInfo.Index.Sub + ']scale=' + $strScaleWidth + ':' + $strScaleHeight + '[subs]'
			$strSubs = "[subs]overlay"
		}
		#Otherwise, We Have No Scaling
		Else {
			#If We Have Cropping, Scale Using The Crop Filter Width / Height
			If ($objInfo.Filter.Crop) {
				$arrCrop = ($objInfo.Filter.Crop.Split('=')[1]).Split(':')
				$strCropWidth = $arrCrop[0]
				$strCropHeight = $arrCrop[1]
				
				$strSubChain = ';[0:' + $objInfo.Index.Sub + ']scale=' + $strCropWidth + ':' + $strCropHeight + '[subs]'
				$strSubs="[subs]overlay"
			}
		}
	}
	#Otherwise Just Use The Regular Subtitle Filter
	Else {
		$strSubs = $objInfo.Filter.Subs
	}
	
	#Set All Of The Filters In The Correct Order By Putting Them Into An Array
	$arrFilters = @($objInfo.Filter.Crop, $objInfo.Filter.Scale, $strSubs)
	
	#Step Through Each Filter And Add It As Needed
	$boolFirstPass = $True
	$arrFilters | % {
		If ($_) {
			#Only Add Video Stream On First Pass
			If ($boolFirstPass) {
				$strFilterChain = $strFilterChain + '[0:' + $ObjInfo.Index.Video + ']' + $_ + '[out]'
				$boolFirstPass = $False
			}
			#Otherwise Add The Filter To The Chain
			Else {
				$strFilterChain = $strFilterChain + ',[out]' + $_ + '[out]'
			}
		}
	}
	
	#If There Is A Filter Chain, Add On The Sub Chain, Which May Be Empty
	If ($strFilterChain) {
		$strFilterChain = $strFilterChain + $strSubChain
	}
	#Otherwise, Pass Video Through The 'Null' Filter.
	Else {
		$strFilterChain = '[0:' + $objInfo.VideoIndex + ']' + 'null[out]'
	}
	
	#Escape Any Semicolons So PowerShell Interprets The Filterchain Correctly
	#This Does Not Seem To Be Needed Anymore (As Of 12/01/2022)
	#$strFilterChain = $strFilterChain.Replace(';',';')
	
	Return $strFilterChain
}

#Escape The Subtitle Video Filter String So PowerShell Interprets It Correctly
Function Escape-Filter ($strInput) {
	#Replace Backslashes
	If ($strInput -match '\\') {$strInput=$strInput.Replace('\', '\\\\')}
	
	#Replace Colons
	If ($strInput -match ':') {$strInput=$strInput.Replace(':', '\\:')}
	
	#Replace Semicolons
	If ($strInput -match ';') {$strInput=$strInput.Replace(';', '\;')}
	
	#Replace Commas
	If ($strInput -match ',') {$strInput=$strInput.Replace(',', '\,')}
	
	#Replace Single Quotes
	If ($strInput -match '''') {$strInput=$strInput.Replace('''', '\\\''')}
	
	#Replace Left Square Brackets
	If ($strInput -match '\[') {$strInput=$strInput.Replace('[', '\[')}
	
	#Replace Right Square Brackets
	If ($strInput -match '\]') {$strInput=$strInput.Replace(']', '\]')}
	
	#Return The Result
	Return $strInput
}

#Unescape The Subtitle Video Filter String So It Can Be Displayed Correctly
Function Unescape-Filter ($strInput) {
	#Replace Backslashes
	If ($strInput -match '\\') {$strInput = $strInput.Replace('\\\\', '\')}
	
	#Replace Colons
	If ($strInput -match ':') {$strInput = $strInput.Replace('\\:', ':')}
	
	#Replace Semicolons
	If ($strInput -match ';') {$strInput = $strInput.Replace('\;', ';')}
	
	#Replace Commas
	If ($strInput -match ',') {$strInput = $strInput.Replace('\,', ',')}
	
	#Replace Single Quotes
	If ($strInput -match '''') {$strInput = $strInput.Replace('\\\''', '''')}
	
	#Replace Left Square Brackets
	If ($strInput -match '\[') {$strInput = $strInput.Replace('\[', '[')}
	
	#Replace Right Square Brackets
	If ($strInput -match '\]') {$strInput = $strInput.Replace('\]', ']')}
	
	#Return The Result
	Return $strInput
}

#Process Parameters Defined In INI File
Function Process-INI ($INIPath, $objParamKeys) {
	#No INI File Defined
	If (!$INIPath) {
		Return
	}
	
	#Gather Parameters From INI File, Skipping Comments / Blank Lines
	$hashINIContent = Get-Content -LiteralPath $INIPath | Where-Object {(($_) -and ($_.Trim)) -and ($_.Trim() -notmatch '^\;')} | Out-String | ConvertFrom-StringData
	
	#Iterate Through All Existing Parameters, Overwriting With Existing INI Values
	$objParamKeys | % {
		#Get The Current Parameter
		$objParam = Get-Variable -Name $_ -ErrorAction SilentlyContinue
		
		#If It Is Valid And Exists In The INI File
		If (($objParam) -and ($hashINIContent.ContainsKey($_))) {
			#If It Is A Switch Parameter, Process As Needed
			If ($objParam.Value -is [System.Management.Automation.SwitchParameter]) {
				Set-Variable -Scope Script -Name $_ -Value (Convert-StringToBool $hashINIContent."$_")
			}
			#Otherwise, The Parameter Does Not Require Processing
			Else {
				Set-Variable -Scope Script -Name $_ -Value $hashINIContent."$_"
			}
		}
	}
}

#Convert INI String Parameters Into Boolean Values
Function Convert-StringToBool ($strInput) {
	$strInput = $strInput.Trim()
	#If An Input String Exists
	If ($strInput) {
		#Try Converting The String Into A Boolean Value
		Try {
			$boolResult = [System.Convert]::ToBoolean($strInput)
		}
		Catch [FormatException] {
			Throw ("Invalid format: '" + $strInput + "'. Use 'True' or 'False' only.")
		}
		
		Return $boolResult
	}
	#Otherwise, Default To A False Value
	Else {
		Return $False
	}
}

#Convert Duration To Sexagesimal Format For Display
Function Convert-ToSexagesimal ([float]$Duration) {
	$strHours = [Math]::Truncate($Duration / 3600)
	$strMins = [Math]::Truncate($Duration / 60)-($strHours * 60)
	$strSecs = $Duration - ($strHours * 3600)-($strMins * 60)
	
	Return ([Int]$strHours).ToString("00") + ':' + ([Int]$strMins).ToString("00") + ':' + ([float]$strSecs).ToString("00.00")
}

#Determines If The Subs Parameter Should Be Enabled / Disabled
#This Function Must Be Called Before Any Language Parameter Checking Occurs
Function Check-Subs ($Subs, $SubIndex, $SubTitle, $SubLang) {
	#If Subtitles Are Enabled Or SubIndex is Defined Or SubTitle Is Defined Or SubLang Is Defined, Return True
	If (($Subs) -or ([Int]$SubIndex -ne -1) -or ($SubTitle) -or ($SubLang)) {
		Return $True
	}
	#Otherwise, Return False
	Else {
		Return $False
	}
}

#Determines If The Scrape Parameter Should Be Enabled / Disabled
#This Function Must Be Called Before Any Language Parameter Checking Occurs
Function Check-Scrape ($Scrape, $ShowQuery, $SeasonQuery, $EpisodeQuery, $ScrapeLang, $SeriesID, $EpisodeOffset) {
	#If Scrape Is Enabled Or Any Query Is Valid Or ScrapeLang Is Defined Or SeriesID Is Defined Or Episode Offset Is Defined, Return True
	If (($Scrape) -or ($ShowQuery) -or ([Int]$SeasonQuery -ne -1) -or ([Int]$EpisodeQuery -ne -1) -or ($ScrapeLang) -or ([Int]$SeriesID -ne -1) -or ([Int]$EpisodeOffset -ne 0)) {
		Return $True
	}
	#Otherwise, Return False
	Else {
		Return $False
	}
}

#Check That The Video Preset Parameter Is Valid
Function Check-VideoPreset($VideoPreset) {
	#Valid Presets
	$arrVideoPresets = @('ultrafast', 'superfast', 'veryfast', 'faster', 'fast', 'medium', 'slow', 'slower', 'veryslow', 'placebo')
	
	#If The Preset Is Valid, Use It
	If ($arrVideoPresets -contains $VideoPreset.ToLower()) {
		Return $VideoPreset
	}
	#Otherwise Throw An Error
	Else {
		Throw ("Invalid preset, valid presets: " + ($arrVideoPresets -join ', '))
	}
}

#Check That The Input Language Parameter Is Valid
Function Check-Lang ($InputLang) {
	#If The Language Is Undefined, Return System Language
	If (!$InputLang)  {
		Return (Get-Culture).ThreeLetterISOLanguageName
	}
	
	#Initialize An Array With All Valid (ISO 639-2) Language Codes
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
	
	#Make Sure The Input Language Is In The Correct Format For Matching
	$InputLang = ($InputLang.ToLower()).Trim()
	
	#If The Input Language Is In $arrLangCodes, Return It
	If ($arrLangCodes -contains $InputLang) {
		Return $InputLang
	}
	
	#Otherwise The Input Language Is Invalid, Throw An Error
	Throw "$InputLang is not valid. Please use ISO 639-2 language codes only:`nhttps://en.wikipedia.org/wiki/List_of_ISO_639-2_codes"
}

#Check The Input Digits Parameter
Function Check-Digits ($strInput) {
	#If It Is Undefined, Return A Default Formatting String
	If (!$strInput) {
		Return '00'
	}
	
	#Try Converting The Input Into An Integer
	#If Is Within The Valid Range, Return The Formatting String
	Try {
		$intOutput = [Int]$strInput
		If ($intOutput -ge 1 -and $intOutput -le 16) {
			Return ('0' * $intOutput)
		}
		#Otherwise The Input Is Invalid, Throw A Blank Error To Be Caught Later
		Else {
			Throw
		}
	}
	#The Input Is Invalid And We Did Not Return, Just Catch And Display The Error
	Catch {
		Throw ("Invalid value for Digits: '" + $strInput + "', please use an integer ranging for 1 - 16. Default is '2' if left blank.")
	}
}

Function Check-Threads ($intThreads) {
	#Input Will Always Be An Integer Between 0-256
	#We Only Need To Make Sure The Thread Count Is No More Than The Number Of Threads The
	#Host Machine Can Handle
	$intHostThreads = (Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors
	If ($intThreads -gt $intHostThreads) {
		#Use ffmpeg's Default Number Of Threads (All)
		Return 0
	}
	Else {
		Return $intHostThreads
	}
}

Function Set-CRF ($intCRF, $strVideoCodec) {
	If ($intCRF -ne -1) {
		Return $intCRF
	}
	
	#Automatically Set CRF, Depending On Video Codec, Using Sane Default Values
	If ($strVideoCodec -eq 'libx264') {
		Return 21
	}
	#Otherwise, We Assume It's libx265
	Else {
		Return 19
	}
}


#Get The INI File Path
#This Function Should Only Be Used With tcs.ps1
Function Get-INIPath ($FilePath, $Rule) {
	#If We Have A Valid Rule
	If ($Rule) {
		#Construct The INI Path
		$INIPath = $PSScriptRoot + '\ini\' + $Rule + '.ini'
		
		#If The INI Path Is Valid, Return It
		If (Test-Path -LiteralPath $INIPath) {
			Return $INIPath
		}
		#Otherwise, The INI Path Is Invalid, Show A Warning And Return The Default INI Path
		Else {
			Write-Warning ("Rule file '" + $INIPath + "' for file: '" + $FilePath + "' does not exist, using 'default'.")
			Return $INIPathDefault
		}
	}
	#Otherwise, No Rule Is Defined, Show A Warning And Return The Default INI Path
	Else {
		Write-Warning ("No rule defined for file: '" + $FilePath + "', using 'default'.")
		Return $INIPathDefault
	}
}

Function Get-Fonts ($objInfo) {
	Try {
	#Create The Font Directory
	New-Item -Path $PSScriptRoot -Name $objInfo.RandomBaseName -ItemType 'Directory' | Out-Null
		
	#Set The Working Directory To The Fonts Directory
	Set-Location ('.\' + $objInfo.RandomBaseName)
	
	#Extract Fonts
	..\bin\ffmpeg.exe -y -loglevel quiet -dump_attachment:t `"`" -i $objInfo.FullName
	}
	Catch {}
	Finally {
		Set-Location $PSScriptRoot
	}
}

Function Check-FrameRate ($floatFrameRate) {
	#We Are Using The Source Frame Rate, Leave At -1.0
	If ([float]$floatFrameRate -eq -1.0) {
		Return $floatFrameRate
	}
	
	#Frame Rate Is Invalid, Show Error
	If ($floatFrameRate -le 0.0) {
		Throw ("Invalid value for Frame Rate: '" + $floatFrameRate + "', please use a number greater than 0.0 and no larger than 1000.0.")
	}
	
	#Return Formatted Frame Rate String
	Return "{0:n3}" -f $floatFrameRate
}

Function Convert-FromSexagesimal ([string]$strDuration) {
	If (!($strDuration)) {
		Return [float]0.0
	}
	
	$strDuration = $strDuration.Replace(',', '.')
	
	$arrDuration = $strDuration.Split(':')
	
	$intHours = [int]$arrDuration[0] * 60 * 60
	$intMins = [int]$arrDuration[1] * 60
	
	$arrSecsAndMils = $arrDuration[2].Split('.')
	
	$intSecs = [int]$arrSecsAndMils[0]
	$decMils = [float]('0.' + $arrSecsAndMils[1])
	
	Return [float]($intHours + $intMins + $intSecs) + $decMils
}

Function Get-Duration ($objFFInfo, $objInfo) {
	#Define Output Format
	$hashDuration = @{
		AsFloat = 0.0
		AsString = ''
		IsMetadata = $False
	}
	
	#Use The Duration Tag If It Is Available
	$strDuration = $objFFInfo.streams[$objInfo.Index.Video].tags | Select-Object -ExpandProperty DURATION* -First 1 -ErrorAction SilentlyContinue
	
	If ($floatDuration) {
		$hashDuration.AsFloat = (Convert-FromSexagesimal $strDuration)
		$hashDuration.AsString = $strDuration
		$hashDuration.IsMetadata = $True
	}
	Else {
		$hashDuration.AsFloat = [float]$objFFInfo.format.duration
		$hashDuration.AsString = Convert-ToSexagesimal $hashDuration.AsFloat
		$hashDuration.IsMetadata = $False
	}
		
	Return $hashDuration
}

Function Get-FrameRate ($objFFInfo, $objInfo, $FrameRate, $boolIsInput) {
	#Initialize Output Hash Table
	$hashFrameRate = @{
		AsString = ''
		AsFloat = 0.0
	}
	
	#Get The Input Frame Rate
	If ($boolIsInput) {
		#If The Video Stream Contains Both Duration And Frame Count Metadata,
		#Calculate The Frame Rate Using That Data
		If ($objInfo.Duration.IsMetaData -and $objInfo.FrameCount.IsMetadata) {
			$hashFrameRate.AsFloat = [float]($objInfo.Input.FrameCount.AsInt * $objInfo.Input.Duration.AsFloat)
			$hashFrameRate.AsString = $hashFrameRate.AsFloat.ToString()
		}
	#Otherwise, Just Use FFmpeg's Reported Frame Rate For The Input Frame Rate
		Else {
			$hashFrameRate.AsString = [string]$objFFInfo.Streams[$objInfo.Index.Video].r_frame_rate
			
			#Convert Fractional Frame Rate Into Float If Needed
			If ($hashFrameRate.AsString -match '/') {
				$arrFrameRate = $hashFrameRate.AsString.Split('/')
				$hashFrameRate.AsFloat = [float]($arrFrameRate[0] / $arrFrameRate[1])
			}
			#Otherwise, Just Convert String Representation To Float
			Else {
				$hashFrameRate.AsFloat = [float]$hashFrameRate.AsString
			}
		}
	}
	#Otherwise, We Are Getting The Output Frame Rate
	Else {
		#If There Is A User Defined Output Frame Rate, Use That
		If ($FrameRate -ne -1.0) {
			$hashFrameRate.AsFloat = $objInfo.Output.FrameRate.AsFloat
			$hashFrameRate.AsString = $objInfo.Output.FrameRate.AsString
		}
		#Otherwise, Match The Input Frame Rate
		#Call This Function As If Were Getting Input Frame Rate Instead
		Else {
			$hashFrameRate = Get-FrameRate $objFFInfo $objInfo -1.0 $True
		}
	}
	
	Return $hashFrameRate
}

Function Get-FrameCount ($objFFInfo, $objInfo) {
	#Define Output Format
	$hashFrameCount = @{
		AsInt = 0
		IsMetadata = $False
	}
	
	#Initialize Frame Rate As Function Wide Variable
	[float]$floatFrameRate = 0.0
	
	#Check For Frame Count Metadata First
	[int]$intFrameCount = $objFFInfo.streams[$objInfo.Index.Video].tags | Select-Object -ExpandProperty NUMBER_OF_FRAMES* -First 1 -ErrorAction SilentlyContinue
	
	#Use Frame Count Metadata If It Is Available
	If ($intFrameCount) {
		$hashFrameCount.AsInt = $intFrameCount
		$hashFrameCount.IsMetadata = $True
	}
	#Otherwise, Derive The Frame Count Manually
	Else {
		$hashFrameCount.AsInt = [int]($objInfo.Input.Duration.AsFloat * (Get-FrameRate $objFFInfo $objInfo -1.0 $True).AsFloat)
		$hashFrameCount.IsMetadata = $False
	}
	
	Return $hashFrameCount
}

Function Check-Replace ($strReplace) {
	#Return If The Input String Is Empty
	If (!$strReplace) {
		Return
	}
	
	#Check That The Input String Is A Single Array Element
	If ($strReplace.Count -ne 1) {
		Throw ("Invalid format (String[]) for Replace: '" + $strReplace + "'. Use a single string only.")
	}
	
	#Split The Input By The Pipe (|) Character
	$arrReplace = $strReplace.Split('|')
	
	#Check That The Input Does Not Contain Empty Elements 
	If (($arrReplace | Where-Object {!($_)}).Count) {
		Throw ("Invalid value for Replace: '" + $strReplace + "'. Empty element(s) found.")
	}
	
	#Check That The Input Is Not Missing Colon Characters
	If (($arrReplace | Where-Object {$_ -notmatch ':'}).Count) {
		Throw ("Invalid value for Replace: '" + $strReplace + "'. Missing colon(s).")
	}
		
	#Check Each Element In The Input String Array
	$arrReplace | % {
		$arrSplit = $_.Split(':')
		
		#Check That We Only Have Two Elements Per Split
		#This Implies Only One Colon Per Array Elemnent, And Allows For
		#Empty Elements
		If ($arrSplit.Count -ne 2) {
			Throw ("Invalid value for Replace: '" + $strReplace + "'. Too many colons.")
		}
		
		#Check That The First String In The Element Is Not Empty
		If (!$arrSplit[0]) {
			Throw ("Invalid value for Replace: '" + $strReplace + "'. Cannot replace an empty string.")
		}
	}
	
	Return $arrReplace
}

Function Get-OutputExtension ($strExtension, $boolNoEncode) {
	If ($boolNoEncode) {
		Return $strExtension
	}
	
	Return '.mp4'
}

Function Check-PixelFormat ($strPixelFormat, $strVideoCodec) {
	$strDefaultPixelFormat = 'yuv420p'
	
	If (!$strPixelFormat) {
		$strPixelFormat = $strDefaultPixelFormat
	}
	
	If (($strPixelFormat -ne 'yuv420p') -and ($strVideoCodec -eq 'libx264')) {
		Write-Warning ("Pixel format: '$strPixelFormat' is poorly supported for Video Codec: '$strVideoCodec'. Forcing 'yuv420p'.")
		
		Return 'yuv420p'
	}
	
	Return $strPixelFormat
}

Function Show-Info ($objFFInfo) {
		$objStreamList = New-Object System.Collections.Generic.List[Object]
		
		$objFFInfo.streams | % {
			If ($_.codec_type -ne 'attachment') {
				$objStream = [ordered]@{
					Index = $_.index
					CodecType = $_.codec_type
					CodecName = $_.codec_name
					Language = $_.tags.language
					Title = $_.tags.title
					Default = [Bool]$_.disposition.default
					Forced = [Bool]$_.disposition.forced
				}
				
				$objStreamList.Add($objStream)
			}
		}
		
		$objStreamList | %{[PSCustomObject]$_} | Format-Table -AutoSize
}

Function Get-VideoRes ($objFFInfo, $objInfo) {
	#Define Output Format
	$hashRes = @{
		Width = 0
		Height = 0
	}
	
	$hashRes.Width = ($objFFInfo.streams[$objInfo.Index.Video]).width
	$hashRes.Height = ($objFFInfo.streams[$objInfo.Index.Video]).height
	
	Return $hashRes
}