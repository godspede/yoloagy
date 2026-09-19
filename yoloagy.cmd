@echo off
rem Windows entry point for yoloagy: runs the bash script beside this file
rem under Git Bash, which drives psmux. Git Bash is resolved explicitly so the
rem WSL bash.exe in System32 cannot shadow it.
set "_GB=%ProgramFiles%\Git\bin\bash.exe"
if not exist "%_GB%" set "_GB=%ProgramW6432%\Git\bin\bash.exe"
if not exist "%_GB%" set "_GB=bash"
"%_GB%" "%~dp0yoloagy" %*
