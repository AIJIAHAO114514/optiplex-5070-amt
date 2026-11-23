@echo off
rem ======================================================================
rem  OptiPlex 5070 AMT 工具箱 - 配置文件
rem  只改这个文件，不要去改 .bat
rem ======================================================================

rem ---- 要写入的 ME 镜像（相对工具箱根目录，也可以写绝对路径）----
set "CFG_ME_FILE=me_amt.bin"

rem ---- 期望的 ME 区域大小（字节）。0 = 不做固定值检查，
rem      只和本机实际的 ME 区域长度逐个比对（推荐 0）----
set "CFG_EXPECT_ME_SIZE=0"

rem ---- 写入成功后是否自动 fpt -greset 立即重启（1=是 0=否）----
set "CFG_GRESET=1"

rem ---- 导出时是否做第二遍 dump 并比对哈希（1=是，更稳；0=省 30 秒）----
set "CFG_DOUBLE_DUMP=1"

rem ---- 导出后是否用 spi_region.py 解析描述符做交叉校验（需要 python）----
set "CFG_AUTO_PARSE=1"

rem ---- MEI 驱动 INF 路径（已随包提供，一般不用改）----
set "CFG_MEI_INF=tools\mei\heci.inf"

rem ---- MEA（ME Analyzer）主脚本，用于判断 File System State ----
set "CFG_MEA=tools\mea\MEA.py"

rem ---- MEA 依赖库目录（随包提供，不要改）----
set "CFG_MEA_LIBS=tools\mea\libs"

rem ---- 工具路径（一般不用改；自测时可用环境变量覆盖）----
if not defined FPT set "FPT=tools\fptw64.exe"
if not defined MEINFO set "MEINFO=tools\MEInfoWin64.exe"
