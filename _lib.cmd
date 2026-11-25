@echo off
rem ======================================================================
rem  _lib.cmd  公共子程序库（被 02_make_me.bat call，不要单独运行）
rem
rem  用法：  call "%~dp0_lib.cmd" :函数名 参数1 参数2 ...
rem  说明：  本文件故意不用 setlocal，函数里 set 的变量会回传给调用者
rem  约定：  参数请一律加引号，函数用 %~2 %~3 取值
rem
rem  本文件只包含 02_make_me.bat 需要的函数。目标机侧不跑批处理，
rem  所有读写都在 UEFI Shell 里用 fpt.efi + nsh 完成。
rem ======================================================================

rem ---- 入口分发：%~1 是 ":函数名"，直接跳过去 ----
if not "%~1"=="" goto %~1
exit /b 0


rem ----------------------------------------------------------------------
rem  :banner  "标题"          打印醒目标题
rem ----------------------------------------------------------------------
:banner
echo.
echo ======================================================================
echo   %~2
echo ======================================================================
echo.
exit /b 0


rem ----------------------------------------------------------------------
rem  :sep                    打印分隔线
rem ----------------------------------------------------------------------
:sep
echo ----------------------------------------------------------------------
exit /b 0


rem ----------------------------------------------------------------------
rem  :need_python            找 python 解释器 -> PY（"python" 或 "py -3"）
rem ----------------------------------------------------------------------
:need_python
set "PY="
where python >nul 2>&1
if not errorlevel 1 set "PY=python"
if defined PY goto :need_python_ok
where py >nul 2>&1
if not errorlevel 1 set "PY=py -3"
if defined PY goto :need_python_ok
echo.
echo [FAIL] 这一步需要 python 3，但 PATH 里找不到 python / py
echo        装一个：https://www.python.org/downloads/
echo        安装时务必勾选 "Add python.exe to PATH"
exit /b 1
:need_python_ok
exit /b 0


rem ----------------------------------------------------------------------
rem  :sha256  "文件"         计算 SHA256 -> SHA（失败则 SHA 为空）
rem ----------------------------------------------------------------------
:sha256
set "SHA="
if not exist "%~2" exit /b 1
for /f "skip=1 delims=" %%h in ('certutil -hashfile "%~2" SHA256 2^>nul') do if not defined SHA set "SHA=%%h"
if not defined SHA exit /b 1
set "SHA=%SHA: =%"
exit /b 0


rem ----------------------------------------------------------------------
rem  :stamp                  生成时间戳 -> STAMP（形如 20261123_2231）
rem ----------------------------------------------------------------------
:stamp
set "STAMP="
set "LDT="
for /f "tokens=2 delims==" %%a in ('wmic os get localdatetime /value 2^>nul ^| find "="') do set "LDT=%%a"
if defined LDT goto :stamp_from_ldt
set "D=%date:~0,10%"
set "D=%D:/=%"
set "D=%D:-=%"
set "D=%D:.=%"
set "D=%D: =%"
set "T=%time: =0%"
set "T=%T::=%"
for /f "tokens=1 delims=." %%a in ("%T%") do set "T=%%a"
set "STAMP=%D%_%T%"
if "%STAMP%"=="" set "STAMP=undated"
exit /b 0
:stamp_from_ldt
set "STAMP=%LDT:~0,4%%LDT:~4,2%%LDT:~6,2%_%LDT:~8,2%%LDT:~10,2%%LDT:~12,2%"
exit /b 0


rem ----------------------------------------------------------------------
rem  :size  "文件"           取文件字节数 -> FSIZE
rem ----------------------------------------------------------------------
:size
set "FSIZE=0"
for %%A in ("%~2") do set "FSIZE=%%~zA"
exit /b 0


rem ----------------------------------------------------------------------
rem  :die  "原因"            打印失败原因并返回 errorlevel 1
rem ----------------------------------------------------------------------
:die
echo.
echo [FAIL] %~2
echo.
exit /b 1
