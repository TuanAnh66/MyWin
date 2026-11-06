@echo off
rem Run this manually in Windows PE if its disk/network controller needs VirtIO.
drvload "%~dp0drivers\vioscsi\vioscsi.inf"
drvload "%~dp0drivers\viostor\viostor.inf"
drvload "%~dp0drivers\netkvm\netkvm.inf"
