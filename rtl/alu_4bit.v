//=============================================================================
// Module: alu_4bit
// Description: 4-bit ALU slice using 4 x alu_1bit_slice cells with
//              ripple carry chain. Two of these form the complete 8-bit ALU.
//
//              Matches the architecture diagram:
//              - Bit 0 (LSB) at bottom, Bit 3 (MSB) at top
//              - Ripple carry: Cin → FA0 → C1 → FA1 → C2 → FA2 → C3 → FA3 → Cout
//              - Shared op_select controls all 4 cells
//=============================================================================

module alu_4bit (
    input  wire [3:0] a,            // Operand A [3:0]
    input  wire [3:0] b,            // Operand B [3:0]
    input  wire       cin,          // Carry-in to Bit 0
    input  wire [1:0] op_select,    // Operation select (shared)
    output wire [3:0] result,       // 4-bit result
    output wire       cout          // Carry-out from Bit 3
);

    // Internal carry chain: C0=Cin, C1, C2, C3, Cout
    wire c1, c2, c3;

    // --- Bit 0 (LSB) ---
    alu_1bit_slice bit0 (
        .a         (a[0]),
        .b         (b[0]),
        .cin       (cin),           // External carry-in
        .op_select (op_select),
        .result    (result[0]),
        .cout      (c1)
    );

    // --- Bit 1 ---
    alu_1bit_slice bit1 (
        .a         (a[1]),
        .b         (b[1]),
        .cin       (c1),            // Carry from Bit 0
        .op_select (op_select),
        .result    (result[1]),
        .cout      (c2)
    );

    // --- Bit 2 ---
    alu_1bit_slice bit2 (
        .a         (a[2]),
        .b         (b[2]),
        .cin       (c2),            // Carry from Bit 1
        .op_select (op_select),
        .result    (result[2]),
        .cout      (c3)
    );

    // --- Bit 3 (MSB) ---
    alu_1bit_slice bit3 (
        .a         (a[3]),
        .b         (b[3]),
        .cin       (c3),            // Carry from Bit 2
        .op_select (op_select),
        .result    (result[3]),
        .cout      (cout)           // Final carry-out
    );

endmodule
