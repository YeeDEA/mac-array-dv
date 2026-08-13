@echo off
REM usage: run_uvm.bat [testname] [seed] [extra xvlog defines e.g. -d BUG3]
setlocal
set TEST=%1
set SEED=%2
if "%TEST%"=="" set TEST=mac_smoke_test
if "%SEED%"=="" set SEED=1
set DEFS=%3 %4 %5

xvlog -sv -L uvm %DEFS% ..\rtl\mac_pe.sv ..\rtl\ctrl.sv ..\rtl\mac_array_4x4.sv ..\rtl\mac_if.sv ^
  ..\sva\mac_array_sva.sv ..\sva\mac_bind.sv mac_pkg.sv tb_top.sv || exit /b 1
xelab tb_top -L uvm -s uvm_sim || exit /b 1
xsim uvm_sim -runall -sv_seed %SEED% -testplusarg UVM_TESTNAME=%TEST%
