@echo off
rem ======================================================================
rem  _lib.cmd  公共子程序库（被其它脚本 call，不要单独双击）
rem
rem  用法：  call "%~dp0_lib.cmd" :函数名 参数1 参数2 ...
rem  说明：  本文件故意不用 setlocal，函数里 set 的变量会回传给调用者
rem  约定：  参数请一律加引号，函数用 %~2 %~3 取值
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
rem  :adm                    检测管理员权限 -> IS_ADMIN=1/0
rem ----------------------------------------------------------------------
:adm
set "IS_ADMIN=0"
reg add "HKLM\SOFTWARE\_amt_toolkit_probe" /f >nul 2>&1
if errorlevel 1 goto :adm_second
reg delete "HKLM\SOFTWARE\_amt_toolkit_probe" /f >nul 2>&1
set "IS_ADMIN=1"
exit /b 0
:adm_second
rem reg.exe 不可用或被策略拦时的兜底：fsutil 需要管理员才能查 USN
fsutil dirty query %SystemDrive% >nul 2>&1
if not errorlevel 1 set "IS_ADMIN=1"
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
echo        说明：只有本步骤（台外 Windows）需要 python，PE 里不需要。
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
rem  :model                  读取机型 -> MODEL / MODEL_SAFE（空格换下划线）
rem ----------------------------------------------------------------------
:model
set "MODEL="
for /f "tokens=2*" %%a in ('reg query "HKLM\HARDWARE\DESCRIPTION\System\BIOS" /v SystemProductName 2^>nul ^| find "SystemProductName"') do set "MODEL=%%b"
if not defined MODEL set "MODEL=unknown"
set "MODEL_SAFE=%MODEL: =_%"
exit /b 0


rem ----------------------------------------------------------------------
rem  :biosver                读取 BIOS 版本 -> BIOSVER
rem ----------------------------------------------------------------------
:biosver
set "BIOSVER="
for /f "tokens=2*" %%a in ('reg query "HKLM\HARDWARE\DESCRIPTION\System\BIOS" /v BIOSVersion 2^>nul ^| find "BIOSVersion"') do set "BIOSVER=%%b"
if not defined BIOSVER set "BIOSVER=unknown"
set "BIOSVER_SAFE=%BIOSVER: =_%"
exit /b 0


rem ----------------------------------------------------------------------
rem  :sn                     读服务编号 -> SN（读不到则为 NOSN）
rem ----------------------------------------------------------------------
:sn
set "SN="
for /f "skip=1 tokens=1" %%a in ('wmic csproduct get identifyingnumber 2^>nul') do if not defined SN set "SN=%%a"
if not defined SN set "SN=NOSN"
set "SN=%SN: =%"
exit /b 0


rem ----------------------------------------------------------------------
rem  :size  "文件"           取文件字节数 -> FSIZE
rem ----------------------------------------------------------------------
:size
set "FSIZE=0"
for %%A in ("%~2") do set "FSIZE=%%~zA"
exit /b 0


rem ----------------------------------------------------------------------
rem  :have  "命令名"         检测命令是否存在 -> HAVE=1/0
rem ----------------------------------------------------------------------
:have
set "HAVE=0"
where %~2 >nul 2>&1
if not errorlevel 1 set "HAVE=1"
exit /b 0


rem ----------------------------------------------------------------------
rem  :die  "原因"            打印失败原因并返回 errorlevel 1
rem ----------------------------------------------------------------------
:die
echo.
echo [FAIL] %~2
echo.
exit /b 1


rem ----------------------------------------------------------------------
rem  :check_tools            检查 FPT 工具是否存在 -> TOOLS_OK=1/0
rem ----------------------------------------------------------------------
:check_tools
set "TOOLS_OK=1"
if not exist "%FPT%" set "TOOLS_OK=0"
if "%TOOLS_OK%"=="0" goto :check_tools_msg
if not exist "tools\fpt.efi" echo [SKIP] 未找到 tools\fpt.efi（只影响 UEFI Shell 备用方案）
exit /b 0
:check_tools_msg
echo [FAIL] 缺少 FPT 主程序：%FPT%
echo        请确认解压时保留了 tools 子目录（不要只拷 .bat 文件）
exit /b 1


rem ----------------------------------------------------------------------
rem  :load_mei               加载随包 MEI 驱动（设备 A360）-> MEI_LOADED=1/0
rem ----------------------------------------------------------------------
:load_mei
set "MEI_LOADED=0"
if not exist "%CFG_MEI_INF%" exit /b 1
echo [ .. ] 尝试加载 Intel MEI 驱动（设备 A360 / CNL-H）
echo        来源：%CFG_MEI_INF%
set "MLOG=%TEMP%\amt_mei_load.txt"
type nul > "!MLOG!" 2>nul
rem WinPE 原生加载器优先；正常 Windows 上没有 drvload，会自动跳过这一句
if exist "%SystemRoot%\System32\drvload.exe" drvload "%CFG_MEI_INF%" >> "!MLOG!" 2>&1
pnputil /add-driver "%CFG_MEI_INF%" /install >> "!MLOG!" 2>&1
type "!MLOG!"
rem 注意：pnputil 失败也返回 0，这里不假装成功，真实结论看随后 fpt 重试
set "MEI_LOADED=1"
echo [ .. ] 加载命令已执行，是否真的生效看下面 fpt 重试的结果
exit /b 0

rem ----------------------------------------------------------------------
rem  :fpt_err "fpt输出文件"  解析 FPT 报错并给出中文对策
rem ----------------------------------------------------------------------
:fpt_err
findstr /i /c:"Error 280" "%~2" >nul 2>&1
if not errorlevel 1 echo   ^>^> Error 280：写保护未解除。断电，装上服务模式跳线（Service Mode），再上电。
findstr /i /c:"Error 368" "%~2" >nul 2>&1
if not errorlevel 1 echo   ^>^> Error 368：BIOS 区域被锁，只允许读写 ME 区域时才用 -me 参数。
findstr /i /c:"Error 1" "%~2" >nul 2>&1
if not errorlevel 1 echo   ^>^> Error 1：多半是 PE 缺 Intel MEI 驱动，或不是管理员权限。
findstr /i /c:"Error 4" "%~2" >nul 2>&1
if not errorlevel 1 echo   ^>^> Error 4：无法访问 SPI，检查跳线、权限、以及是否被 BIOS 锁住。
findstr /i /c:"Error 167" "%~2" >nul 2>&1
if not errorlevel 1 echo   ^>^> Error 167：区域被锁（PRR/FLOCKDN），需要断电重插跳线后再试。
findstr /i /c:"FPT Operation Successful" "%~2" >nul 2>&1
if not errorlevel 1 echo   ^>^> 提示：输出里出现 FPT Operation Successful，说明该步成功。
exit /b 0

rem ----------------------------------------------------------------------
rem  :mea_check "MEA输出文件"  解析 File System State -> MEA_STATE
rem       Configured / Initialized / unknown，返回值 0=识别成功 1=没识别
rem ----------------------------------------------------------------------
:mea_check
set "MEA_STATE=unknown"
if not exist "%~2" exit /b 1
findstr /i /c:"File System State" "%~2" >nul 2>&1
if errorlevel 1 goto :mea_check_bad
echo   ---- MEA 关键行 ----
findstr /i /c:"FW Version" /c:"MEBx Version" /c:"File System State" /c:"FPF" /c:"Capability Licensing" "%~2"
echo   --------------------
findstr /i /c:"File System State" "%~2" | findstr /i "Configured" >nul 2>&1
if not errorlevel 1 set "MEA_STATE=Configured"
findstr /i /c:"File System State" "%~2" | findstr /i "Initialized" >nul 2>&1
if not errorlevel 1 set "MEA_STATE=Initialized"
exit /b 0
:mea_check_bad
echo   [SKIP] MEA 没能识别这个文件（可能不是合法 ME 区域）
exit /b 1
