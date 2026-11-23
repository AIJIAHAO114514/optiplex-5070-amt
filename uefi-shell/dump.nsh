@echo -off
if exist fpt.efi then
  echo ====================================================
  echo   Dump full SPI, about 32MB. Do NOT power off.
  echo ====================================================
  fpt.efi -d full.bin
  echo 
  echo   Dump ME region only ...
  fpt.efi -me -d me.bin
  echo 
  ls
  echo 
  echo   Done. Copy full.bin and me.bin back to the PC.
endif
if not exist fpt.efi then
  echo ====================================================
  echo   fpt.efi not found in the current folder.
  echo   Type:  map
  echo   Then:  fs0:    fs1:    fs2:   ... until dir shows fpt.efi
  echo   Then:  dump.nsh
  echo ====================================================
endif
