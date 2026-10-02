# 8085 Microprocessor — 8-Bit ALU (Verilog Implementation)

## Project Overview

Complete Verilog implementation of the **8-bit ALU** for the **Intel 8085 microprocessor**, built from the ground up using a hierarchical bit-slice architecture with an FSM-based controller.

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                      alu_8085_top                            │
│                                                              │
│  ┌────────────────┐  Control Signals  ┌───────────────────┐  │
│  │ FSM Controller │ ───────────────►  │    8-bit ALU      │  │
│  │ (S0 → S5)      │ ◄─────────────── │   ┌───────────┐   │  │
│  └────────────────┘  Flag Feedback    │   │4-bit High │   │  │
│                                       │   │  [7:4]    │   │  │
│  ┌────────────┐  ┌──────────────┐     │   │   ↕ AC    │   │  │
│  │Accumulator │  │ Flag Register│     │   │4-bit Low  │   │  │
│  │  A [7:0]   │  │ S,Z,AC,P,CY │     │   │  [3:0]    │   │  │
│  └────────────┘  └──────────────┘     │   └───────────┘   │  │
│                                       │  Logic | Rotate    │  │
│                                       └───────────────────┘  │
└──────────────────────────────────────────────────────────────┘
```

## File Structure

```
8 bit alu/
├── rtl/                            ← Synthesizable Verilog source
│   ├── full_adder.v                   1-bit Full Adder (gate-level)
│   ├── alu_1bit_slice.v               1-bit ALU cell (FA + Logic + MUX)
│   ├── alu_4bit.v                     4-bit ALU slice (4 × 1-bit cells + carry chain)
│   ├── rotate_unit.v                  Rotate operations (RLC/RRC/RAL/RAR)
│   ├── flag_generator.v              Flag computation (S, Z, AC, P, CY)
│   ├── alu_8bit.v                     8-bit ALU (2 × 4-bit slices + logic + rotate)
│   ├── fsm_controller.v              FSM controller (S0→S5 state machine)
│   └── alu_8085_top.v                 Top-level integration module
│
├── tb/                             ← Testbenches
│   ├── tb_full_adder.v                Full Adder exhaustive test (8 cases)
│   ├── tb_alu_4bit.v                  4-bit ALU arithmetic + logic tests
│   ├── tb_alu_8bit.v                  8-bit ALU all 16 operations test
│   └── tb_alu_8085_top.v             Full integration test (FSM pipeline)
│
├── sim/                            ← Simulation scripts
│   └── run_sim.bat                    Windows batch script for iverilog
│
├── docs/                           ← Architecture diagrams
│   └── (architecture images)
│
└── README.md                       ← This file
```

## Module Hierarchy

```
alu_8085_top                    ← Top-level (clocked)
├── fsm_controller              ← 6-state FSM (S0-S5)
└── alu_8bit                    ← 8-bit ALU (combinational)
    ├── alu_4bit (Low [3:0])    ← 4-bit slice
    │   ├── alu_1bit_slice × 4  ← 1-bit cells
    │   │   └── full_adder      ← Gate-level FA
    ├── alu_4bit (High [7:4])   ← 4-bit slice (carry-chained)
    │   ├── alu_1bit_slice × 4
    │   │   └── full_adder
    ├── rotate_unit             ← RLC/RRC/RAL/RAR
    └── flag_generator          ← S, Z, AC, P, CY
```

## Supported Operations

| Opcode | Operation | Instruction | Description |
|--------|-----------|-------------|-------------|
| `0000` | ADD       | ADD r/M     | A ← A + B |
| `0001` | ADC       | ADC r/M     | A ← A + B + CY |
| `0010` | SUB       | SUB r/M     | A ← A - B |
| `0011` | SBB       | SBB r/M     | A ← A - B - CY |
| `0100` | ANA       | ANA r/M     | A ← A & B |
| `0101` | XRA       | XRA r/M     | A ← A ^ B |
| `0110` | ORA       | ORA r/M     | A ← A \| B |
| `0111` | CMP       | CMP r/M     | A - B (flags only) |
| `1000` | RLC       | RLC         | Rotate left circular |
| `1001` | RRC       | RRC         | Rotate right circular |
| `1010` | RAL       | RAL         | Rotate left through carry |
| `1011` | RAR       | RAR         | Rotate right through carry |
| `1100` | CMA       | CMA         | A ← ~A |
| `1101` | STC       | STC         | CY ← 1 |
| `1110` | CMC       | CMC         | CY ← ~CY |
| `1111` | INR       | INR r       | A ← A + 1 |

## Flag Register

```
Bit:  7    6    5    4    3    2    1    0
    ┌────┬────┬────┬────┬────┬────┬────┬────┐
    │ S  │ Z  │ -- │ AC │ -- │ P  │ -- │ CY │
    └────┴────┴────┴────┴────┴────┴────┴────┘
```

## FSM Controller States

```
S0 (IDLE) ──start──► S1 (LOAD_A) ──► S2 (LOAD_B) ──► S3 (LOAD_OP)
                                                          │
S5 (DONE) ◄──────── S4 (EXECUTE) ◄───────────────────────┘
    │
    └──► S0 (IDLE)
```

## How to Simulate

### Using Icarus Verilog (iverilog)

```bash
# Run all tests
cd sim
run_sim.bat

# Run individual tests
run_sim.bat full_adder
run_sim.bat alu_4bit
run_sim.bat alu_8bit
run_sim.bat alu_8085_top
```

### Manual compilation

```bash
# Compile and run the 8-bit ALU test
iverilog -o alu_8bit_test.vvp rtl/*.v tb/tb_alu_8bit.v
vvp alu_8bit_test.vvp

# View waveforms
gtkwave alu_8bit.vcd
```

### Using ModelSim / Questa

```tcl
vlib work
vlog rtl/*.v tb/tb_alu_8085_top.v
vsim -c tb_alu_8085_top -do "run -all; quit"
```

### Using Vivado (Xilinx)

1. Create new project, add all `rtl/*.v` files as Design Sources
2. Add `tb/*.v` files as Simulation Sources
3. Set `tb_alu_8085_top` as top simulation module
4. Run Behavioral Simulation
