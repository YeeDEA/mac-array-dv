@echo off
REM W1 sanity: compile & simulate the SystemVerilog toy on Vivado 2020.2 xsim.
REM Run from a shell where Vivado is on PATH (or run settings64.bat first, e.g.:
REM   call C:\Xilinx\Vivado\2020.2\settings64.bat)
xvlog -sv toy_sv.sv || exit /b 1
xelab toy_tb -s toy_sim || exit /b 1
xsim toy_sim -runall
