@echo off
REM ==========================================================================
REM  8085 ALU Simulation Script — Icarus Verilog (iverilog)
REM  Usage: run_sim.bat [test_name]
REM    test_name: full_adder | alu_4bit | alu_8bit | alu_8085_top (default: all)
REM ==========================================================================

setlocal enabledelayedexpansion

set RTL_DIR=..\rtl
set TB_DIR=..\tb
set OUT_DIR=.\output

REM Create output directory
if not exist %OUT_DIR% mkdir %OUT_DIR%

REM RTL source files (in dependency order)
set RTL_FILES=%RTL_DIR%\full_adder.v %RTL_DIR%\alu_1bit_slice.v %RTL_DIR%\alu_4bit.v %RTL_DIR%\rotate_unit.v %RTL_DIR%\flag_generator.v %RTL_DIR%\alu_8bit.v %RTL_DIR%\fsm_controller.v %RTL_DIR%\alu_8085_top.v

if "%1"=="" goto run_all
if "%1"=="full_adder" goto run_full_adder
if "%1"=="alu_4bit" goto run_alu_4bit
if "%1"=="alu_8bit" goto run_alu_8bit
if "%1"=="alu_8085_top" goto run_alu_8085_top
echo Unknown test: %1
echo Usage: run_sim.bat [full_adder ^| alu_4bit ^| alu_8bit ^| alu_8085_top]
goto end

:run_all
echo ======================================================
echo  Running ALL testbenches
echo ======================================================
echo.

:run_full_adder
echo ------ Full Adder Test ------
iverilog -o %OUT_DIR%\tb_full_adder.vvp %RTL_DIR%\full_adder.v %TB_DIR%\tb_full_adder.v
if errorlevel 1 (echo [ERROR] Compilation failed! & goto next1)
cd %OUT_DIR% && vvp tb_full_adder.vvp && cd ..
:next1
echo.
if not "%1"=="" if not "%1"=="full_adder" goto end
if "%1"=="full_adder" goto end

:run_alu_4bit
echo ------ 4-bit ALU Test ------
iverilog -o %OUT_DIR%\tb_alu_4bit.vvp %RTL_DIR%\full_adder.v %RTL_DIR%\alu_1bit_slice.v %RTL_DIR%\alu_4bit.v %TB_DIR%\tb_alu_4bit.v
if errorlevel 1 (echo [ERROR] Compilation failed! & goto next2)
cd %OUT_DIR% && vvp tb_alu_4bit.vvp && cd ..
:next2
echo.
if "%1"=="alu_4bit" goto end

:run_alu_8bit
echo ------ 8-bit ALU Test ------
iverilog -o %OUT_DIR%\tb_alu_8bit.vvp %RTL_FILES% %TB_DIR%\tb_alu_8bit.v
if errorlevel 1 (echo [ERROR] Compilation failed! & goto next3)
cd %OUT_DIR% && vvp tb_alu_8bit.vvp && cd ..
:next3
echo.
if "%1"=="alu_8bit" goto end

:run_alu_8085_top
echo ------ 8085 ALU Top Integration Test ------
iverilog -o %OUT_DIR%\tb_alu_8085_top.vvp %RTL_FILES% %TB_DIR%\tb_alu_8085_top.v
if errorlevel 1 (echo [ERROR] Compilation failed! & goto next4)
cd %OUT_DIR% && vvp tb_alu_8085_top.vvp && cd ..
:next4
echo.

:end
echo ======================================================
echo  Simulation Complete
echo  VCD waveforms saved in %OUT_DIR%\
echo  Open with GTKWave: gtkwave %OUT_DIR%\[filename].vcd
echo ======================================================
endlocal
