@echo off
rem ======================================================================
rem  配置文件 —— 只改这个文件，不要去改 .bat
rem
rem  本工具箱只做一件事：从整片 dump 或 FIT 产物里裁出 ME 区。
rem  目标机的读写由 UEFI Shell 里的 fpt.efi + nsh 完成，不走批处理。
rem ======================================================================

rem ---- 要产出的 ME 镜像文件名（相对仓库根目录，也可写绝对路径）----
set "CFG_ME_FILE=me_amt.bin"

rem ---- MEA（ME Analyzer）主脚本，用于判断 File System State ----
set "CFG_MEA=tools\mea\MEA.py"

rem ---- MEA 依赖库目录（随仓库提供，不要改）----
set "CFG_MEA_LIBS=tools\mea\libs"
