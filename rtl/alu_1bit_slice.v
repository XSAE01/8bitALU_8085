//=============================================================================
// Module: alu_1bit_slice
// Description: 1-bit ALU cell — the bit-slice building block.
//              Contains a Full Adder, Logic Block (AND/OR/XOR), and 4:1 MUX.
//              4 of these are instantiated to form a 4-bit ALU slice.
//
// Op Select encoding:
//   2'b00 = AND (ANA/ANI)
//   2'b01 = OR  (ORA/ORI)
//   2'b10 = XOR (XRA/XRI)
//   2'b11 = Arithmetic (ADD/ADC/SUB/SBB/CMP/INR/DCR)
//=============================================================================

module alu_1bit_slice (
    input  wire       a,            // Operand A bit
    input  wire       b,            // Operand B bit
    input  wire       cin,          // Carry-in (for Full Adder)
    input  wire [1:0] op_select,    // Operation select
    output wire       result,       // ALU result bit
    output wire       cout          // Carry-out (from Full Adder)
);

    // --- Logic Block: parallel computation ---
    wire and_result;
    wire or_result;
    wire xor_result;

    assign and_result = a & b;
    assign or_result  = a | b;
    assign xor_result = a ^ b;

    // --- Full Adder: arithmetic computation ---
    wire fa_sum;

    full_adder fa_inst (
        .a    (a),
        .b    (b),
        .cin  (cin),
        .sum  (fa_sum),
        .cout (cout)
    );

    // --- 4:1 MUX: operation select ---
    reg mux_out;

    always @(*) begin
        case (op_select)
            2'b00:   mux_out = and_result;   // AND
            2'b01:   mux_out = or_result;    // OR
            2'b10:   mux_out = xor_result;   // XOR
            2'b11:   mux_out = fa_sum;       // Arithmetic (Full Adder Sum)
            default: mux_out = 1'b0;
        endcase
    end

    assign result = mux_out;

endmodule
