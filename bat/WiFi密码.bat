@echo off
title ������鿴�������ӹ���WiFi���ƺ�����
echo. & echo ���ù���ԱȨ�����д���������������޷���ȡ������
echo.
for /f "tokens=3*" %%i in ('netsh wlan show profiles ^| findstr "�����û������ļ�"') do (
call :GetPass %%i %%j
)
pause
goto :eof
 
:GetPass
echo,WiFi : %*
setlocal enabledelayedexpansion
for /f "delims=" %%a in ('netsh wlan show profile name^="%*" key^=clear ^| findstr "�ؼ�����"') do (
set var=%%a
set var1=!var:�ؼ�����=����!
set var2=!var1: =!
set var3=!var2:^:= : !
echo,!var3!
)
echo,=========================
endlocal
goto :eof