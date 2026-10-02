//=============================================================================
// Module: flag_generator
// Description: 8085 Flag Generator — computes all 5 flags.
//
// Flag Register layout: [ S | Z | - | AC | - | P | - | CY ]
//                  Bit:   7   6   5   4    3   2   1   0
//
// Flag logic:
//   S  (Sign)           = Result[7]
//   Z  (Zero)           = ~|Result  (NOR of all bits)
//   AC (Auxiliary Carry) = Carry from bit 3 → bit 4
//   P  (Parity)         = ~^Result  (even parity: XOR tree, inverted)
//   CY (Carry)          = Carry-out from bit 7
//=============================================================================

module flag_generator (
    input  wire [7:0] result,       // ALU result
    input  wire       carry_out,    // Carry-out from MSB (bit 7)
    input  wire       aux_carry,    // Carry from bit 3 → bit 4
    output wire       flag_s,       // Sign flag
    output wire       flag_z,       // Zero flag
    output wire       flag_ac,      // Auxiliary Carry flag
    output wire       flag_p,       // Parity flag (even parity)
    output wire       flag_cy       // Carry flag
);

    // S flag: MSB of result (1 = negative in 2's complement)
    assign flag_s  = result[7];

    // Z flag: set when result is zero
    assign flag_z  = (result == 8'h00);

    // AC flag: carry between lower and upper nibble
    assign flag_ac = aux_carry;

    // P flag: even parity (set when even number of 1s in result)
    assign flag_p  = ~(^result);   // XOR tree, inverted

    // CY flag: carry/borrow out of bit 7
    assign flag_cy = carry_out;

endmodule
