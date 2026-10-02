//=============================================================================
// Module: rotate_unit
// Description: 8085 Rotate Unit — implements the four rotate operations.
//              Only the Accumulator is rotated; CY flag participates in
//              RAL and RAR (rotate through carry).
//
// Rotate encoding (rot_select):
//   2'b00 = RLC  (Rotate Left Circular)   — bit7 → CY and bit0
//   2'b01 = RRC  (Rotate Right Circular)  — bit0 → CY and bit7
//   2'b10 = RAL  (Rotate Left thru Carry) — bit7 → CY, old CY → bit0
//   2'b11 = RAR  (Rotate Right thru Carry)— bit0 → CY, old CY → bit7
//=============================================================================

module rotate_unit (
    input  wire [7:0] a,            // Accumulator value
    input  wire       carry_in,     // Current CY flag value
    input  wire [1:0] rot_select,   // Rotate operation select
    output reg  [7:0] result,       // Rotated result
    output reg        carry_out     // New CY flag value
);

    always @(*) begin
        case (rot_select)
            // RLC: Rotate Left Circular
            // CY ← bit7; {bit7..bit1} ← {bit6..bit0}; bit0 ← bit7
            2'b00: begin
                result    = {a[6:0], a[7]};
                carry_out = a[7];
            end

            // RRC: Rotate Right Circular
            // CY ← bit0; {bit6..bit0} ← {bit7..bit1}; bit7 ← bit0
            2'b01: begin
                result    = {a[0], a[7:1]};
                carry_out = a[0];
            end

            // RAL: Rotate Left through Carry
            // CY ← bit7; {bit7..bit1} ← {bit6..bit0}; bit0 ← old CY
            2'b10: begin
                result    = {a[6:0], carry_in};
                carry_out = a[7];
            end

            // RAR: Rotate Right through Carry
            // CY ← bit0; {bit6..bit0} ← {bit7..bit1}; bit7 ← old CY
            2'b11: begin
                result    = {carry_in, a[7:1]};
                carry_out = a[0];
            end

            default: begin
                result    = a;
                carry_out = carry_in;
            end
        endcase
    end

endmodule
