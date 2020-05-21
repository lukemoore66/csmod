@echo off

echo %~2 | find /i "rss-">Nul && (
echo %~1^|%~2>>%~dpn0.txt
)