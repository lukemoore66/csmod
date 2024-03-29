# csmod

A PowerShell script that transcodes / renames video files into a highly compatible format. It can be used standalone, or in conjunction with qBittorrent.

It features:
* Automatic audio / subtitle stream selection based on language preferences.
* Automatic renaming of output files using information scraped from TheTVDB.
* Automatic audio normalization.
* High quality AAC audio encoding using qaac (Apple's CoreAudio AAC encoder).

## Getting Started

Click the 'Releases' button, download the latest version, then unzip everything to a folder of your choice and run cs.ps1 in a PowerShell prompt. You will require [7-zip](https://www.7-zip.org/) to do this.


Typical usage looks like this:
```
.\cs.ps1 -InputPath 'C:\Path\To\Input\Files' -Subs -Rename -Scrape 'C:\Path\To\Output\Files'
```

The above command will transcode all video files in the InputPath, burn in subtitles, and rename them by scraping relevant information from TheTVDB. 

Don't forget the quotation marks around file and folder paths, they are needed for PowerShell to take things literally. Files and folders can also be dragged and dropped into the PowerShell window to fill in the file paths.

For a full list of parameters, input the following into a PowerShell Prompt:
```
.\cs.ps1 -
```
Followed by <kbd>Ctrl</kbd> + <kbd>Space</kbd>

If you want to use this script with qBittorrent, cut and paste the following into the `Run external program upon torrent completion` field within the `Options -> Downloads` menu:
```
WScript.exe "C:\Path\to\csmod\tcsi.vbs" "%F" "%L"
```

Replacing the script path with your own.

Then, use the RSS Downloader function to assign categories that correspond with base name of the corresponding configuration file in the `ini` folder.

For example, setting the category to `rss-anime`, will cause csmod to use the `rss-anime.ini` configuration file.

When creating new ini files, always use the `rss-default.ini` file as a template.

All ini files must follow the `rss-nameofini.ini` naming format.

Whenever a torrent has finished downloading, the torrent is queued in `tsci.txt`.

When you want to process all torrents contained in `tcsi.txt`, open a PowerShell prompt and run:
```
.\tcs.ps1
```

### Prerequisites

PowerShell 7.0 or higher is required. You will have to download the latest version of [PowerShell](https://github.com/PowerShell/PowerShell) manually if you are running an older version. This script will only run on Windows.

Scripts are disabled by default in Windows systems, they need to be enabled for csmod to run. For more information please visit [about_Execution_Policies
](https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_execution_policies?view=powershell-7.2).

This script uses large temporary files when running, therefore, it is not recommended to run it off an SSD.

## Uses
[ffmpeg](https://www.ffmpeg.org/) - Video Transcoder

[qaac](https://github.com/nu774/qaac) - Audio Transcoder

[libFLAC](https://github.com/xiph/flac) - Audio Decoder

[aacgain](https://github.com/dgilman/aacgain) - Audio Normalizer

[mp4box](https://gpac.wp.imt.fr/) - Muxer

[PurpleBooth](https://github.com/PurpleBooth) - Readme Template

## Authors

* **Luke Moore** - [lukemoore66](https://github.com/lukemoore66)

## License

This project is licensed under the MIT License - see the [LICENSE.md](/LICENSE.md) file for details.

## Acknowledgments

* Hat tip to ffmpeg / qaac / xiph.org / aacgain / GPAC devs.
* Inspiration: HandBrake, but with a better quality audio encoder, automated stream selection based on the user's language preferences, and a scraper for the automatic renaming of output files.
