#Gets Video Index From Input File Info Object
Function Get-VideoIndex ($objInfo, $VideoIndex) {
	#Get A List Of Video Streams
	$objVideoStreams = $objInfo.streams | Where-Object {($_.codec_type -eq 'video') -and ($objStreamInfo.disposition.attached_pic -ne 1)}
	
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
Function Get-SubIndex ($objInfo, $SubIndex, $SubLang, $SubTitle, $Subs) {
	#Subtitles Disabled
	If (!$Subs) {
		Return -1
	}
	
	#Get A List Of Subtitle Streams
	$objSubStreams = $objInfo.streams | Where-Object {$_.codec_type -eq 'subtitle'}
	
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
Function Get-AudioIndex ($objInfo, $AudioIndex, $AudioLang, $AudioTitle, $NoAudio) {
	#Audio Disabled
	If ($NoAudio) {
		Return -1
	}
	
	#Get A List Of Audio Streams
	$objAudioStreams = $objInfo.streams | Where-Object {$_.codec_type -eq 'audio'}
	
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
	If ($AudioTitle -ne $null) {
		$intTitleIndex = ($objAudioStreams | Where-Object {$_.tags.title -eq $AudioTitle}).index | Select-Object -First 1
		If ($intTitleIndex -ne $null) {
			Return $intTitleIndex
		}
	}
	
	#Use Audio Language
	if ($AudioLang -ne $null) {
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
		
	#Check If Forced Crop Is Enabled And Valid
	If ($ForceCrop) {
		#Get Crop Values
		$arrForceCrop = $ForceCrop.Split(':')
		$intInputWidth = ($objInfo.streams[$objInfo.VideoIndex]).width
		$intInputHeight = ($objInfo.streams[$objInfo.VideoIndex]).height
		$intTotalWidth = $arrForceCrop[0] + $arrForceCrop[2]
		$intTotalHeight = $arrForceCrop[1] + $arrForceCrop[3]

		#If Forced Crop Is Within Width / Height Bounds, Use That
		If (($intTotalWidth -le $intInputWidth) -and ($intTotalHeight -le $intInputHeight ) -and ($intTotalWidth -ge $MinRes.Split(':'[0])) -and ($intTotalHeight -ge $MinRes.Split(':'[1]))) {
			Return 'crop=' + $ForceCrop
		}
		#Otherwise, Show A Warning, Then Run Auto Crop Anyway
		Else {
			Write-Warning ("Forced crop '$ForceCrop' is out of bounds, using auto-crop.")
		}
	}
	
	#Start Auto Cropping
	$intTotalIterations=10
	$intFrameAmt=30
	
	$intMaxWidth = 0
	$intMaxHeight = 0
	$intMinWidthOffset = 0
	$intMinHeightOffset = 0

	$intSeekChunk = $objInfo.format.duration / $intTotalIterations
	
	#Run Auto Crop
	$intCropCounter = 0
	While ($intCropCounter -lt $intTotalIterations) {
		$floatSeekSeconds = $intCropCounter * $intSeekChunk
		[Int]$intSeekSeconds = $floatSeekSeconds
		
		#Run FFmpeg
		$strCropDetect = .\bin\ffmpeg.exe -ss $intSeekSeconds -i $objInfo.FullName -vframes $intFrameAmt -vf cropdetect=24:4 -an -sn -f null nul 2>&1
		
		#Split Ffmpeg Output String To Get Crop Parameters
		$strCrop = [regex]::Split([regex]::Split($strCropDetect, 'crop=')[-1], "`r`n")[0].Trim()
		
		#Get Crop Values
		$arrCrop = [regex]::Split($strCrop,':')
		
		If ([Int]$arrCrop[0] -gt $intMaxWidth) {
			$intMaxWidth = $arrCrop[0]
		}
		
		If ([Int]$arrCrop[1] -gt $intMaxHeight) {
			$intMaxHeight = $arrCrop[1]
		}
		
		If ([Int]$arrCrop[2] -lt $intMinWidthOffset) {
			$intMinWidthOffset = $arrCrop[2]
		}
		
		If ([Int]$arrCrop[3] -lt $intMinHeightOffset) {
			$intMinHeightOffset = $arrCrop[3]
		}
		
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
	
	#If Height / Width Has Not Changed, Do Nothing
	If ((($objInfo.streams[$objInfo.VideoIndex]).width -eq $intMaxWidth) -and (($objInfo.streams[$objInfo.VideoIndex]).height -eq $intMaxHeight)) {
		If (($intMinWidthOffset -eq 0) -and ($intMinHeightOffset -eq 0)) {
			Return $null
		}
	}
	
	Return "crop=$intMaxWidth`:$intMaxHeight`:$intMinWidthOffset`:$intMinHeightOffset"
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
	If ($objInfo.Crop -ne $null) {
		$arrCrop = ($objInfo.Crop.Split('='))[-1].Split(':')
		$intInputWidth = [Int]$arrCrop[0]
		$intInputHeight = [Int]$arrCrop[1]
	}
	#Otherwise, Get The Original Resolution And Use Those Values For The Input Width / Height
	Else {
		$intInputWidth = ($objInfo.streams[$objInfo.VideoIndex]).width
		$intInputHeight = ($objInfo.streams[$objInfo.VideoIndex]).height
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
Function Set-Subs ($objInfo, $ForceRes, $Subs) {
	#Return Null If No Subs Found Or Subs Disabled
	If ($objInfo.SubIndex -eq -1) {
		Return $null
	}
		
	#Set Up The Filter If Subtitles Are PGS
	$objSubStream = $objInfo.streams | Where-Object {$_.index -eq $objInfo.SubIndex}
	If (($objSubStream.codec_name -eq 'hdmv_pgs_subtitle') -or ($objSubStream.codec_name -eq 'dvd_subtitle')) {
		Return '[0:' + $objInfo.SubIndex + ']overlay'
	}
	
	#Otherwise Enumerate All Non PGS Subtitles So The 'Subtitle' Filter
	$intSubFilterIndex = 0
	$objInfo.streams | Where-Object {$_.codec_type -eq 'subtitle'} | % {
		If (($_.codec_name -ne 'hdmv_pgs_subtitle') -and ($_.codec_name -ne 'dvd_subtitle')) {
			If ($_.index -eq $objInfo.SubIndex) {
				#If Resolution Is Forced, We Have To Maintain Original Aspect Ratio
				If ($ForceRes) {
					$strSubForceRes = ':original_size=' + ($objInfo.streams[$objInfo.VideoIndex]).width + 'x' + ($objInfo.streams[$objInfo.VideoIndex]).height
				}
				
				Return 'subtitles="' + (Escape-Filter $objInfo.FullName) + '":si=' + $intSubFilterIndex + $strSubForceRes
			}
			$intSubFilterIndex++
		}
	}
}

#Clean Up The Input Name
Function Clean-Name ($strInput, $Replace) {
	#Convert To Lowercase
	$strInput = $strInput.ToLower()
	
	#Process Any String Replacements
	If ($Replace) {
		$Replace | % {
			$arrStringReplace = $_.Split(':')
			If ($arrStringReplace[0]) {
				$strReplaceIn = $arrStringReplace[0].ToLower()
			}
			
			If ($arrStringReplace[1]) {
				$strReplaceOut = $arrStringReplace[1].ToLower()
			}
			
			$strInput = $strInput.Replace($strReplaceIn, $strReplaceOut)
		}
	}
	
	#Clean Between '[' And ']'
	$strInput = $strInput -replace '\[.*?\](?![^\[\]]*\])', ''

	#Clean Between '(' And ')'
	$strInput = $strInput -replace '\(.*?\)(?![^\(\)]*\))', ''
	
	#Replace '.' With ' '
	$strInput = $strInput.Replace('.', ' ')

	#Replace '_' With ' '
	$strInput = $strInput.Replace('_', ' ')

	#Remove Any Accented Characters
	[char[]]$strInput.Normalize('FormD') | % {
		If ([System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($_) -ne 'NonSpacingMark') {
			$strNoAccents = $strNoAccents + $_
		}
	}
	$strInput = $strNoAccents
	
	#Replace Invalid File System Characters With '-'
	$strInvalidChars = [IO.Path]::GetInvalidFileNameChars() -join ''
	$strRename = '[{0}]' -f [RegEx]::Escape($strInvalidChars)
	$strInput = $strInput -replace $strRename, '-'
	
	#Replace '`'  With '''
	$strInput = $strInput -replace "``", "'"

	#Replace ':' With '-'
	$strInput = $strInput -replace ':', '-'
	
	#Trim Whitespace / Dashes From Either End Of The Input String
	$strInput = $strInput.Trim(' ', '-')
	
	#Convert Multiple Spaces To Single Spaces
	$strInput = $strInput -replace '\s+', ' '
	
	#Convert To Title Case
	$strInput = (Get-Culture).TextInfo.ToTitleCase($strInput)
	
	#Make The Sxxexx String The Correct Format
	If ($strInput -match ' (s|S)\d{1,2}(e|E)\d{1,2}( |$)') {
		$strInput = $strInput.Replace($Matches[0], $Matches[0].ToUpper())
	}
	
	Return $strInput
}

#Get The Full Output Name Path
Function Get-FullNameOutput ($objInfo, $OutputPath, $Scrape, $ScrapeLang, $CleanName, $EpisodeOffset, $SeriesID, $Digits) {
	#Get All Required Info, Fills Out ObjInfo With Needed Data
	Get-NameInfo $objInfo $Scrape $ScrapeLang $EpisodeOffset $SeriesID
	
	#If Scraping Was Enabled
	If ($Scrape) {
		#If All Info Is Available, Build The Full Output Name
		If (($objInfo.ShowTitle) -and ([Int]$objInfo.SeasonNumber -gt -1) -and ([Int]$objInfo.EpisodeNumber -gt -1) -and ($objInfo.EpisodeTitle)) {
			$strEpisodeNumber = ([Int]$objInfo.EpisodeNumber).ToString($Digits)
			$strSeasonNumber = ([Int]$objInfo.SeasonNumber).ToString($Digits)
			
			Return ($OutputPath + '\' + $objInfo.ShowTitle + '\Season ' + $strSeasonNumber + '\' + $objInfo.ShowTitle + ' S' + $strSeasonNumber + 'E' + $strEpisodeNumber + ' - ' + $objInfo.EpisodeTitle + '.mp4')
		}
	}
	
	#If Clean Name Is Enabled, Use The Cleaned Name Only
	If (($CleanName) -and ($objInfo.BaseNameCleaned)) {
		Return ($OutputPath + '\' + $objInfo.BaseNameCleaned + '.mp4')
	}
		
	#Otherwise, Use The Input Name
	Return ($OutputPath + '\' + $objInfo.BaseName + '.mp4')
}

#Get Info For Making Full Output Name
Function Get-NameInfo ($objInfo, $Scrape, $ScrapeLang, $EpisodeOffset, $SeriesID) {
	#Use ' SxxExx' Regex Pattern To Get Season And Episode Numbers
	If ($objInfo.BaseNameCleaned -match ' S\d{1,2}E\d{1,2}( |$)') {
		#Get Season And Episode Number Sting
		$strSeasonEp = ($Matches[0]).Trim()
		
		#If No Show Query, Get The Show Title
		If (!$objInfo.ShowTitle) {
			$objInfo.ShowTitle = (($objInfo.BaseNameCleaned -split $strSeasonEp)[0]).Trim()
		}
		
		#If No Season Query, Get The Season Number
		If ([Int]$objInfo.SeasonNumber -le -1) {
			$objInfo.SeasonNumber = ((($strSeasonEp.Split('E'))[0]).TrimStart('S'))
		}
		
		#If No Episode Query, Get The Episode Number
		If ([Int]$ObjInfo.EpisodeNumber -le -1) {
			$objInfo.EpisodeNumber = [Int](($strSeasonEp.Split('E'))[1]) + $EpisodeOffset
		}
	}
	#Otherwise There Was No Info Matched From BaseNameCleaned
	Else {
		#If Scraping Was Enabled And No Season Number And Episode Number Is Defined, Show A Warning
		If (($Scrape) -and ([Int]$objInfo.SeasonNumber -le -1) -and ([Int]$ObjInfo.EpisodeNumber -le -1)) {
			Write-Warning ("Could not match cleaned input name '" + $objInfo.BaseNameCleaned + "' for scraping. Try to match the format: 'Show Title S01E01'")
		}
	}
	
	#Only Scrape If Scrape Is Enabled, And Show / Season / Episode Are All Defined
	If ($Scrape) {
		If (($objInfo.ShowTitle) -and ([Int]$objInfo.SeasonNumber -gt -1) -and ([Int]$objInfo.EpisodeNumber -gt -1)) {
			$objInfo.EpisodeTitle = Scrape-EpisodeTitle $objInfo $ScrapeLang $SeriesID
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
		$strURL = 'http://thetvdb.com/api/GetSeries.php?seriesname=' + ([uri]::EscapeDataString($objInfo.ShowTitle))
		
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
			Write-Warning ("No show title scrape data found for: " + $objInfo.ShowTitle)
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
	$strURL = 'http://www.thetvdb.com/api/' + $strAPIKey + '/series/' + $strSeriesID + '/' + $strEpOrder + '/' + $objInfo.SeasonNumber + '/' + $objInfo.EpisodeNumber + '/' + $ScrapeLang
	
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
		Write-Warning ("No episode title scrape data found for: '" + $objInfo.ShowTitle + "'")
		Return $null
	}

	#Set The Episode Title From Scraped Data
	$strEpisodeTitle = $xmlInfo.Data.Episode.EpisodeName
	
	#Clean Up The Scraped Title To Construct A Valid File Name
	#Remove Any Accented Characters
	[char[]]$strEpisodeTitle.Normalize('FormD') | % {
		If ([System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($_) -ne 'NonSpacingMark') {
			$strNoAccents = $strNoAccents + $_
		}
	}
	$strEpisodeTitle = $strNoAccents
	
	#Replace Invalid File System Chars With '-'
	$strInvalidChars = [IO.Path]::GetInvalidFileNameChars() -join ''
	$strRename = '[{0}]' -f [RegEx]::Escape($strInvalidChars)
	$strEpisodeTitle = $strEpisodeTitle -replace $strRename, '-'

	#Replace '`'  With '''
	$strEpisodeTitle = $strEpisodeTitle -replace "``", "'"

	#Replace ':' With '-'
	$strEpisodeTitle = $strEpisodeTitle -replace ':', '-'
	
	#Convert Multiple Spaces To Single Spaces
	$strEpisodeTitle = $strEpisodeTitle -replace '\s+', ' '
	
	#Trim Whitespace From Either End Of The Input String
	$strEpisodeTitle = $strEpisodeTitle.Trim()

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
	$objSubStream = $objInfo.streams | Where-Object {$_.index -eq $objInfo.SubIndex}
	If (($objSubStream.codec_name -eq 'hdmv_pgs_subtitle') -or ($objSubStream.codec_name -eq 'dvd_subtitle')) {
		#If We Have Scaling, Scale PGS Subtitles Using The Same Resolution As The Scale Filter
		If ($objInfo.Scale) {
			$strScaleWidth = ((($objInfo.Scale.Split('='))[1]).Split(':'))[0]
			$strScaleHeight = ((($objInfo.Scale.Split('='))[1]).Split(':'))[1]
			
			$strSubChain = ';[0:' + $objInfo.SubIndex + ']scale=' + $strScaleWidth + ':' + $strScaleHeight + '[subs]'
			$strSubs = "[subs]overlay"
		}
		#Otherwise, We Have No Scaling
		Else {
			#If We Have Cropping, Scale Using The Crop Filter Width / Height
			If ($objInfo.Crop) {
				$strCropWidth = ((($objInfo.Crop.Split('='))[1]).Split(':'))[0]
				$strCropHeight = ((($objInfo.Crop.Split('='))[1]).Split(':'))[1]
				
				$strSubChain = ';[0:' + $objInfo.SubIndex + ']scale=' + $strCropWidth + ':' + $strCropHeight + '[subs]'
				$strSubs="[subs]overlay"
			}
		}
	}
	#Otherwise Just Use The Regular Subtitle Filter
	Else {
		$strSubs = $objInfo.Subs
	}
	
	#Set All Of The Filters In The Correct Order By Putting Them Into An Array
	$arrFilters = @($objInfo.Crop, $objInfo.Scale, $strSubs)
	
	#Step Through Each Filter And Add It As Needed
	$boolFirstPass = $True
	$arrFilters | % {
		If ($_) {
			#Only Add Video Stream On First Pass
			If ($boolFirstPass) {
				$strFilterChain = $strFilterChain + '[0:' + $ObjInfo.VideoIndex + ']' + $_ + '[out]'
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
	$strFilterChain = $strFilterChain.Replace(';','`;')
	
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
			#If It Is An Array Of Strings, Process As Needed
			ElseIf ($objParam.Value -is [System.String[]]) {
				Set-Variable -Scope Script -Name $_ -Value (Convert-StringToArray $hashINIContent."$_")
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

#Convert INI String To An Array Of Strings
Function Convert-StringToArray ($strInput) {
	#If An Input String Exists
	If ($strInput) {
		$strInput = $strInput.Trim()
		
		#Make Sure The String Is Enclosed In '\\' Characters
		If ($strInput[0] -eq '\'  -and $strInput[-1] -eq '\') {
			#Trim Off The Surrounding '\\' Characters
			#(One '\') Is Escaped On Either Side In Process-INI Using ConvertFrom-StringData
			$strInput = $strInput.Trim('\')
			
			#Return The Split String, Using '|' As The Split Character
			Return [String[]]$strInput.Split('|')
		}
		#Otherwise Throw An Error, As The Input Is Invalid
		Else {
			Throw ("Invalid format: '" + $strInput + "'. Enclose input in '\\'s.")
		}
	}
}

#Convert Duration To Sexagesimal Format For Display
Function Get-Sexagesimal ([float]$Duration) {
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
	
	#Make Sure The Input Language Is In The Correct Format For Matching
	If ($InputLang -match '^(([a-z][a-z][a-z])|([A-Z][A-Z][A-Z]))$') {
		$InputLang = ($InputLang.ToLower()).Trim()
		
		#If The Input Language Is In The langcodes.dat File, Return It
		If ((Get-Content .\res\langcodes.dat | Where-Object {$_ -match $InputLang})) {
			Return $InputLang
		}
	}
	#Otherwise The Input Language Is Invalid, Throw An Error
	Else {
		Throw "$InputLang is not valid. Please use ISO 639-2 language codes only:`nhttps://en.wikipedia.org/wiki/List_of_ISO_639-2_codes"
	}
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