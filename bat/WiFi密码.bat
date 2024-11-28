@echo off
title 批处理查看所有连接过的WiFi名称和密码
echo. & echo 请用管理员权限运行此批处理，否则可能无法获取到密码
echo.
for /f "tokens=3*" %%i in ('netsh wlan show profiles ^| findstr "所有用户配置文件"') do (
call :GetPass %%i %%j
)
pause
goto :eof
 
:GetPass
echo,WiFi : %*
setlocal enabledelayedexpansion
for /f "delims=" %%a in ('netsh wlan show profile name^="%*" key^=clear ^| findstr "关键内容"') do (
set var=%%a
set var1=!var:关键内容=密码!
set var2=!var1: =!
set var3=!var2:^:= : !
echo,!var3!
)
echo,=========================
endlocal
goto :eof