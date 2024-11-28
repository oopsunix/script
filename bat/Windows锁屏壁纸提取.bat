
@echo OFF

setlocal enabledelayedexpansion

Title 提取win10锁屏壁纸工具

rem yyyymmdd 为格式  // _%time:~0,2%%time:~3,2%%time:~6,2%

set yyyymmdd=%date:~0,4%%date:~5,2%%date:~8,2%

set originPath=C:\Users\%username%\AppData\Local\Packages\Microsoft.Windows.ContentDeliveryManager_cw5n1h2txyewy\LocalState\Assets\

rem echo %originPath%

set tFile="目录"

set tName="文件名"

set folder="images"

rem 删除images旧数据
if exist %folder% (
    cd %folder%
    del /q *.*
    cd ..
)

if not exist %folder% (

md %folder%

)

:STEP1

for /f "Delims=" %%i in ('dir /s /b /o:-s %originPath%') do (

set tFile=%%i

set tName=%%~ni

copy %%i %folder%

)

:STEP2

cd %folder%

set /a index=0

for /f "delims=" %%x in ('dir /s /b /o:-s *.*') do (

set /a index+=1

ren "%%x" "!index!-!yyyymmdd!-%%~nx.jpg"

)

:exit

exit
