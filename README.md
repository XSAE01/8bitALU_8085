# 8085 Microprocessor — 8-Bit ALU (Verilog Implementation)

## Project Overview

Complete Verilog implementation of the **8-bit ALU** for the **Intel 8085 microprocessor**, built from the ground up using a hierarchical bit-slice architecture with an FSM-based controller.

## Architecture

![alu_8085_top block diagram](docs/alu_8085_top.svg)

The subsystem loads A, B and the opcode through a 6-state FSM, computes in a
combinational 8-bit ALU built from two 4-bit bit-slices, and writes the result
back to the Accumulator and the new flags to the Flag Register. Full details,
including the datapath, bit-slice and FSM diagrams, are in
[docs/architecture.md](docs/architecture.md).

## File Structure

```
8 bit alu/
├── rtl/                            ← Synthesizable Verilog source
│   ├── full_adder.v                   1-bit Full Adder (gate-level)
│   ├── alu_1bit_slice.v               1-bit ALU cell (FA + logic + 4:1 MUX)
│   ├── alu_4bit.v                     4-bit ALU slice (4 × 1-bit cells, ripple carry)
│   ├── rotate_unit.v                  Rotate operations (RLC/RRC/RAL/RAR)
│   ├── flag_generator.v               Flag computation (S, Z, AC, P, CY)
│   ├── alu_8bit.v                     8-bit ALU (operand select + 2 slices + rotate + flags)
│   ├── fsm_controller.v               FSM controller (S0→S5)
│   └── alu_8085_top.v                 Top-level: registers + FSM + ALU
│
├── tb/                             ← Testbenches
│   ├── tb_full_adder.v                Full Adder, all 8 cases
│   ├── tb_alu_4bit.v                  4-bit slice, exhaustive (2,048 cases)
│   ├── tb_alu_8bit.v                  8-bit ALU, exhaustive (4,194,304 cases)
│   ├── tb_alu_8085_top.v              Full pipeline: exhaustive sweep, BCD, DAD
│   └── alu_ref_model.vh               Shared reference model (`include)
│
├── sim/
│   └── run_sim.bat                    Windows script for Icarus Verilog
│                                      (writes to sim/output/, git-ignored)
│
├── docs/
│   ├── architecture.md                Design description
│   ├── alu_8085_top.svg               Subsystem block diagram
│   ├── alu_8bit_architecture.svg      8-bit ALU datapath
│   ├── alu_4bit_slice.svg             1-bit cell and 4-bit slice
│   └── fsm_controller.svg             FSM state diagram
│
└── README.md
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

`alu_op` is 5 bits. Immediate forms (ADI, ACI, SUI, SBI, ANI, XRI, ORI, CPI)
use the same operation with the immediate byte as B.

| Opcode  | Operation | Instruction | Description | Flags |
|---------|-----------|-------------|-------------|-------|
| `00000` | ADD       | ADD r/M     | A ← A + B | all |
| `00001` | ADC       | ADC r/M     | A ← A + B + CY | all |
| `00010` | SUB       | SUB r/M     | A ← A - B | all (CY = borrow) |
| `00011` | SBB       | SBB r/M     | A ← A - B - CY | all (CY = borrow) |
| `00100` | ANA       | ANA r/M     | A ← A & B | S,Z,P; AC=1; CY=0 |
| `00101` | XRA       | XRA r/M     | A ← A ^ B | S,Z,P; AC=0; CY=0 |
| `00110` | ORA       | ORA r/M     | A ← A \| B | S,Z,P; AC=0; CY=0 |
| `00111` | CMP       | CMP r/M     | A - B (flags only) | all (CY = borrow) |
| `01000` | RLC       | RLC         | Rotate left circular | CY |
| `01001` | RRC       | RRC         | Rotate right circular | CY |
| `01010` | RAL       | RAL         | Rotate left through carry | CY |
| `01011` | RAR       | RAR         | Rotate right through carry | CY |
| `01100` | CMA       | CMA         | A ← ~A | none |
| `01101` | STC       | STC         | CY ← 1 | CY |
| `01110` | CMC       | CMC         | CY ← ~CY | CY |
| `01111` | INR       | INR r/M     | A ← A + 1 | S,Z,AC,P |
| `10000` | DCR       | DCR r/M     | A ← A - 1 | S,Z,AC,P |
| `10001` | DAA       | DAA         | Decimal adjust A after addition | all |
| `10010` | DADL      | DAD rp (1/2)| A ← A + B (A = L, B = rp low) | CY |
| `10011` | DADH      | DAD rp (2/2)| A ← A + B + CY (A = H, B = rp high) | CY |
| `10100`–`11111` | — | reserved    | no-op (A and flags unchanged) | none |

**DAD** is a 16-bit add (HL ← HL + rp). Like the real 8085, it runs as two
8-bit ALU passes: issue DADL on the low bytes, then DADH on the high bytes.
The final CY is the 16-bit carry; S, Z, AC and P are not affected.

**AC after subtraction** (SUB, SBB, CMP, DCR) is the carry out of the low
nibble of the two's-complement add A + ~B + 1, not a half-borrow.

INX/DCX are not ALU operations: the 8085 performs them in a separate 16-bit
incrementer/decrementer and they affect no flags.

## Flag Register

`flags_out` is `{S, Z, AC, P, CY}`; `flag_reg_out` packs them in the 8085
PSW layout, with the unused bits driven to 0:

```
Bit:  7    6    5    4    3    2    1    0
    ┌────┬────┬────┬────┬────┬────┬────┬────┐
    │ S  │ Z  │ 0  │ AC │ 0  │ P  │ 0  │ CY │
    └────┴────┴────┴────┴────┴────┴────┴────┘
```

Reset values: S = 0, Z = 1, AC = 0, P = 1, CY = 0 (consistent with A = 00h).

## FSM Controller

![FSM state diagram](docs/fsm_controller.svg)

One operation: `start` is sampled in S0, then S1 (load A) → S2 (load B) →
S3 (latch opcode) → S4 (result and flags written on the clock edge leaving
S4; CMP skips the A write) → S5 (`done` high) → S0.

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

The exhaustive sweeps take a while: about 1.5 minutes for `alu_8bit` and
3 minutes for `alu_8085_top` with Icarus Verilog.

### Manual compilation

```bash
# Compile and run the 8-bit ALU test
# (-I tb lets the testbenches `include tb/alu_ref_model.vh)
iverilog -I tb -o alu_8bit_test.vvp rtl/*.v tb/tb_alu_8bit.v
vvp alu_8bit_test.vvp

# View waveforms
gtkwave alu_8bit.vcd
```

### Using ModelSim / Questa

```tcl
vlib work
vlog +incdir+tb rtl/*.v tb/tb_alu_8085_top.v
vsim -c tb_alu_8085_top -do "run -all; quit"
```

### Using Vivado (Xilinx)

1. Create new project, add all `rtl/*.v` files as Design Sources
2. Add `tb/*.v` and `tb/alu_ref_model.vh` as Simulation Sources
3. Set `tb_alu_8085_top` as top simulation module
4. Run Behavioral Simulation
