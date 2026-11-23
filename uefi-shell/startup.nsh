@echo -off
cls
echo ==========================================================
echo   OptiPlex 5070 AMT toolkit   UEFI Shell
echo ==========================================================
echo 
echo   Filesystems on this machine:
map
echo 
echo   If the prompt shows only "Shell>" then no current folder
echo   is set. Do this first:
echo        fs0:            (or fs1: fs2: ...)
echo        dir             (until you see fpt.efi)
echo        dump.nsh
echo 
echo   Two scripts:
echo        dump.nsh    full SPI to full.bin  +  ME region to me.bin
echo        write.nsh   write me_amt.bin into ME region only
echo 
