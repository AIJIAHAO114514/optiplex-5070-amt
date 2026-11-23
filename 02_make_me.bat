@echo off
chcp 936 >nul 2>&1
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"
title 步骤2 - 生成 ME 镜像（FIT 前 / 后）
call "%~dp0config.cmd"
set "LIB=%~dp0_lib.cmd"
set "PYTHONPATH=%CD%\%CFG_MEA_LIBS%"

rem ---- 命令行参数（必须在菜单接管前抓住）----
set "RAW1=%~2"
set "RAW2=%~3"
set "MODE=%~1"

if /i "%MODE%"=="" goto :menu
if /i "%MODE%"=="fit-input" goto :input_mode
if /i "%MODE%"=="fit-output" goto :output_mode
if /i "%MODE%"=="info" goto :info_mode
call "%LIB%" :die "未知参数：%MODE%（可用：fit-input / fit-output / info）"
goto :fatal

rem ======================================================================
rem  交互菜单
rem ======================================================================
:menu
call "%LIB%" :banner "步骤 2 / 4   生成 ME 镜像（在正常 Windows 上跑）"
echo   本步骤需要 python 3，用途有两个：
echo     [1] FIT 之前：从 01 导出的全片里裁出 ME 区，作为参照
echo     [2] FIT 之后：从 FIT 输出的 outimage.bin 里裁出 me_amt.bin（刷写用）
echo.
echo     [3] 只看某个镜像的分区表
echo     [Q] 退出
echo.
set "SEL="
set /p "SEL=  请选择："
if /i "%SEL%"=="1" goto :menu_input
if /i "%SEL%"=="2" goto :menu_output
if /i "%SEL%"=="3" goto :menu_info
if /i "%SEL%"=="q" goto :fatal
echo   输入无效，重来。
pause
goto :menu

:menu_input
echo.
set "ARG1="
set /p "ARG1=  把 01 生成的 2_full_dump.bin 拖进来后回车："
goto :input_mode

:menu_output
echo.
set "ARG1="
set /p "ARG1=  把 FIT 输出的 outimage.bin 拖进来后回车："
set "ARG2="
set /p "ARG2=  再把本机的 2_full_dump.bin 拖进来后回车："
goto :output_mode

:menu_info
echo.
set "ARG1="
set /p "ARG1=  把要看的镜像拖进来后回车："
goto :info_mode

rem ======================================================================
rem  [1] FIT 输入：从全片裁出 ME 区
rem ======================================================================
:input_mode
call "%LIB%" :banner "FIT 输入：从全片裁出 ME 区域"
if defined ARG1 goto :input_clean
set "ARG1=%RAW1%"
:input_clean
set "ARG1=%ARG1:"=%"
if not "%ARG1%"=="" goto :input_check
set /p "ARG1=  full_dump 路径："
set "ARG1=%ARG1:"=%"
:input_check
if not exist "%ARG1%" goto :no_file
call "%LIB%" :need_python
if errorlevel 1 goto :fatal
call "%LIB%" :sep
%PY% "tools\spi_region.py" info "%ARG1%"
if errorlevel 1 goto :bad_image

for %%A in ("%ARG1%") do set "DIR=%%~dpA"
set "MEOUT=%DIR%me_region_for_fit.bin"
echo.
echo [ .. ] 裁出 ME 区域 -^> %MEOUT%
%PY% "tools\spi_region.py" extract "%ARG1%" ME "%MEOUT%"
if errorlevel 1 goto :bad_image

echo.
if not exist "%DIR%3_me_region.bin" goto :input_done
echo [ .. ] 与本机 fpt 直读的 3_me_region.bin 交叉校验 ...
%PY% "tools\spi_region.py" check-pair "%ARG1%" "%DIR%3_me_region.bin"
if errorlevel 1 goto :pair_bad
echo [ OK ] 交叉校验通过：描述符裁剪结果与 fpt 直读的 ME 区完全一致
:input_done
echo.
call "%LIB%" :banner "下一步：在 FIT 里重组 ME"
echo   1) 打开 FIT：CSME System Tools v12 r36\Flash Image Tool\WIN32\fit.exe
echo   2) File -^> Open，打开 %ARG1%
echo   3) 左侧 Flash Layout 选中 ME Region，替换成干净的
echo      12.0.68.1606_COR_H_BA_PRD_RGN.bin
echo      （拿不到 RGN 时，可先对照 me_region_for_fit.bin 看原厂结构）
echo   4) Build Settings 里打开 AMT / KVM / SOL 对应开关
echo   5) Build -^> Build Image，产物默认 outimage.bin
echo.
echo   注意：Build 完不要直接刷，先跑 02_make_me.bat fit-output 裁出 me_amt.bin
echo.
pause
exit /b 0

:pair_bad
echo [FAIL] 描述符裁剪结果与 fpt 直读的 ME 区域不一致
echo        说明 01 的 dump 或描述符解析有问题，先别拿去 FIT
goto :fatal

rem ======================================================================
rem  [2] FIT 输出：裁出 me_amt.bin
rem ======================================================================
:output_mode
call "%LIB%" :banner "FIT 输出：生成 me_amt.bin"
if defined ARG1 goto :output_clean1
set "ARG1=%RAW1%"
:output_clean1
set "ARG1=%ARG1:"=%"
if not "%ARG1%"=="" goto :output_check1
set /p "ARG1=  FIT 输出的 outimage.bin 路径："
set "ARG1=%ARG1:"=%"
:output_check1
if not exist "%ARG1%" goto :no_file
if defined ARG2 goto :output_clean2
set "ARG2=%RAW2%"
:output_clean2
set "ARG2=%ARG2:"=%"
if not "%ARG2%"=="" goto :output_start
echo   本机 2_full_dump.bin 路径（直接回车可跳过对比，不建议跳）：
set /p "ARG2=  > "
set "ARG2=%ARG2:"=%"
:output_start
call "%LIB%" :need_python
if errorlevel 1 goto :fatal

call "%LIB%" :sep
%PY% "tools\spi_region.py" info "%ARG1%"
if errorlevel 1 goto :bad_image

rem ---- 对比：除 ME 之外有没有被改动 ----
set "CHK=SKIP"
if "%ARG2%"=="" goto :no_compare
if not exist "%ARG2%" goto :no_compare
echo.
echo [ .. ] 与原始 dump 逐区域对比（ME 区除外）...
%PY% "tools\spi_region.py" compare "%ARG1%" "%ARG2%" --ignore-me --ignore-desc
if errorlevel 1 goto :bios_changed
set "CHK=OK"
goto :do_extract

:bios_changed
echo.
echo [FAIL] BIOS 或 GbE 区被改了（这两个区必须一个字节都不变）
echo        只写 ME 的话它们不会落盘，但仍建议先搞清楚原因：
echo          - 打开的不是这台机器的 dump
echo          - 在 FIT 里动过 BIOS 相关设置（Dell BIOS 有签名校验，一改就过不了）
echo        描述符区若只有几个字节差异，属 FIT 重排 PCH strap，不在本脚本写入范围内。
echo.
set "ANS="
set /p "ANS=  强行继续？输入 YES 继续，其它任意键退出："
if /i not "%ANS%"=="YES" goto :fatal
set "CHK=WARN"
goto :do_extract

:no_compare
echo [SKIP] 没给原始 dump，跳过 BIOS 对比（建议补上，这是防刷错图的关键一步）

:do_extract
echo.
echo [ .. ] 从 FIT 输出里裁出 ME 区域 ...
%PY% "tools\spi_region.py" extract "%ARG1%" ME "%CFG_ME_FILE%"
if errorlevel 1 goto :bad_image
echo.
%PY% "tools\spi_region.py" check-me "%CFG_ME_FILE%"
if errorlevel 1 goto :bad_me

rem ---- 与原始 ME 长度比对 ----
if "%ARG2%"=="" goto :mea
call "%LIB%" :size "%CFG_ME_FILE%"
set "SZ_NEW=!FSIZE!"
set "TMPME=%TEMP%\amt_orig_me.bin"
%PY% "tools\spi_region.py" extract "%ARG2%" ME "%TMPME%" >nul 2>&1
call "%LIB%" :size "%TMPME%"
set "SZ_ORIG=!FSIZE!"
del "%TMPME%" >nul 2>&1
if "!SZ_NEW!"=="!SZ_ORIG!" goto :size_ok
echo.
echo [FAIL] ME 区长度变了：原始 !SZ_ORIG! 字节，FIT 输出 !SZ_NEW! 字节
echo        fpt -f xxx -me 要求两者严格相等，这样刷不进去。
echo        回 FIT 检查 Build Settings 与 Flash Layout。
goto :fatal
:size_ok
echo [ OK ] ME 区长度与原始一致：!SZ_NEW! 字节

rem ---- MEA 判定 File System State ----
:mea
set "MEA_STATE=unknown"
if not exist "%CFG_MEA%" goto :sidecar
if not defined PY goto :sidecar
call "%LIB%" :stamp
set "MEALOG=logs\mea_!STAMP!.txt"
echo.
echo [ .. ] 用 MEA 分析 me_amt.bin（看 File System State）...
%PY% "%CFG_MEA%" -skip -exit -duc "%CFG_ME_FILE%" > "!MEALOG!" 2>&1
call "%~dp0_lib.cmd" :mea_check "!MEALOG!"
if /i "!MEA_STATE!"=="Configured" goto :mea_ok
if /i "!MEA_STATE!"=="Initialized" goto :mea_init
echo   [SKIP] MEA 没给出 File System State（日志：!MEALOG!）
goto :sidecar
:mea_ok
set "MEA_STATE=Configured"
echo [ OK ] File System State = Configured，符合开 AMT 的前提
goto :sidecar
:mea_init
set "MEA_STATE=Initialized"
echo [FAIL] File System State 还是 Initialized —— 刷进去大概率仍然只有 ISM
echo        回查：RGN 换了没？FIT 里 Build Settings 的 AMT 开关开了没？

rem ---- 写伴随文件 ----
:sidecar
call "%LIB%" :size "%CFG_ME_FILE%"
set "SZ_NEW=!FSIZE!"
call "%LIB%" :sha256 "%CFG_ME_FILE%"
set "H_NEW=!SHA!"
call "%LIB%" :stamp
set "SC=%CFG_ME_FILE%.txt"
echo ====================================================== > "!SC!"
echo  me_amt.bin 说明（02_make_me.bat 生成）>> "!SC!"
echo ====================================================== >> "!SC!"
echo SIZE=!SZ_NEW! >> "!SC!"
echo SHA256=!H_NEW! >> "!SC!"
echo MEA_STATE=!MEA_STATE! >> "!SC!"
echo BIOS_CHECK=!CHK! >> "!SC!"
echo OUTIMAGE=%ARG1% >> "!SC!"
echo ORIG_DUMP=%ARG2% >> "!SC!"
echo BUILT=!STAMP! >> "!SC!"

echo.
call "%LIB%" :banner "me_amt.bin 已生成"
echo   文件：%CD%\%CFG_ME_FILE%
echo   大小：!SZ_NEW! 字节
echo   哈希：!H_NEW!
echo   状态：!MEA_STATE!   （BIOS 对比：!CHK!）
echo.
echo   下一步：把 me_amt.bin 与 me_amt.bin.txt 拷到 U 盘工具箱根目录，
echo   目标机进 PE 后跑 03_flash_me.bat
echo.
pause
exit /b 0

rem ======================================================================
rem  [3] 只看分区表
rem ======================================================================
:info_mode
if defined ARG1 goto :info_clean
set "ARG1=%RAW1%"
:info_clean
set "ARG1=%ARG1:"=%"
if not "%ARG1%"=="" goto :info_check
set /p "ARG1=  镜像路径："
set "ARG1=%ARG1:"=%"
:info_check
if not exist "%ARG1%" goto :no_file
call "%LIB%" :need_python
if errorlevel 1 goto :fatal
%PY% "tools\spi_region.py" info "%ARG1%"
echo.
pause
exit /b 0

rem ======================================================================
rem  异常出口
rem ======================================================================
:no_file
call "%LIB%" :die "文件不存在：%ARG1%"
goto :fatal

:bad_image
call "%LIB%" :die "不是完整的 SPI 镜像（描述符解析失败）：%ARG1%"
echo        正常应为 32MB 整（33554432 字节），FIT 的 outimage.bin 也一样
goto :fatal

:bad_me
call "%LIB%" :die "裁出来的 ME 区域不像合法镜像（$FPT 魔数不对）"
echo        回 FIT 看 Build Image 是否真的成功
goto :fatal

:fatal
echo.
pause
exit /b 1
