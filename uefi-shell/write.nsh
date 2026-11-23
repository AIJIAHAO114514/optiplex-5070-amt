@echo -off
echo ====================================================
echo   Step 1 of 3   back up the current ME region
echo ====================================================
fpt.efi -me -d me_before.bin
echo ====================================================
echo   Step 2 of 3   write ME region only
echo   Do NOT power off during this step
echo ====================================================
fpt.efi -f me_amt.bin -me
echo ====================================================
echo   Step 3 of 3   read back for verification
echo ====================================================
fpt.efi -me -d me_after.bin
ls
echo ====================================================
echo   Done. Power off, unplug the power cord,
echo   remove the service jumper, then power on.
echo   Copy me_after.bin back to the PC for checking.
echo ====================================================
