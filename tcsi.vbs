'Create Regex Object For Matching Label Parameter
Set reRSS = New RegExp
reRSS.Pattern = "^rss-.*$"
reRSS.IgnoreCase = True

'If The Label Argument Matches The Correct Pattern
If reRSS.Test(WScript.Arguments(1)) Then
	'Open The File To Be Written To
	Set objFileToWrite = CreateObject("Scripting.FileSystemObject").OpenTextFile(Replace(WScript.ScriptFullName, ".vbs", ".txt"), 8, True)
	
	'Append Arguments To The Opened File, Removing Any Quotation Marks From The Arguments
	objFileToWrite.WriteLine(Replace(WScript.Arguments(0), """", "") & "|" & WScript.Arguments(1))
	
	'Clean Up
	objFileToWrite.Close
	Set objFileToWrite = Nothing
End If

'Clean-Up And Exit
Set reRSS = Nothing
WScript.Quit
