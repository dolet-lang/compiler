@echo off
setlocal
python "%~dp0scripts\bootstrap.py" %*
exit /b %errorlevel%
