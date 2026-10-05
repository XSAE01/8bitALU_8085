//=============================================================================
// File: alu_ref_model.vh
// Description: Behavioral reference model for the 8085 ALU, shared by
//              tb_alu_8bit and tb_alu_8085_top. `include it inside a module.
//              Written with plain wide arithmetic rather than the slice/carry
//              structure of the RTL, so it is an independent check.
//
// Flag rules ({S, Z, AC, P, CY}; any flag not listed is unchanged):
//   ADD/ADC         : all flags; AC = carry out of the low nibble
//   SUB/SBB/CMP     : all flags; CY = borrow; AC = low-nibble carry of
//                     A + ~B + ~borrow_in (two's-complement AC)
//   INR             : S, Z, AC, P; CY unchanged
//   DCR             : S, Z, AC, P; CY unchanged; AC = low-nibble carry of
//                     A + FFh, i.e. A[3:0] != 0 (same convention as SUB)
//   ANA             : S, Z, P; AC = 1; CY = 0
//   XRA/ORA         : S, Z, P; AC = 0; CY = 0
//   RLC/RRC/RAL/RAR : CY only
//   CMA             : no flags
//   STC / CMC       : CY = 1 / CY = ~CY
//   DAA             : all flags; +06h if A[3:0] > 9 or AC; +60h (and CY = 1)
//                     if A > 99h or CY; AC = carry out of the low nibble
//   DADL / DADH     : CY only (carry out of A + B / A + B + CY)
//   reserved        : no flags
//=============================================================================

function [4:0] ref_flags;          // {S, Z, AC, P, CY}
    input [7:0] a, b;
    input [4:0] op;
    input [4:0] fin;
    reg   [8:0] wide;
    reg   [4:0] nib;
    reg   [7:0] r;
    reg   [7:0] corr;
    reg         cy;
    begin
        cy        = fin[0];
        ref_flags = fin;             // Default: every flag unchanged
        r         = 8'h00;
        case (op)
            5'b00000, 5'b00001: begin  // ADD, ADC
                wide = a + b + (op[0] & cy);
                nib  = a[3:0] + b[3:0] + (op[0] & cy);
                r    = wide[7:0];
                ref_flags = {r[7], r == 8'h00, nib[4], ~^r, wide[8]};
            end
            5'b00010, 5'b00011, 5'b00111: begin  // SUB, SBB, CMP
                wide = {1'b0, a} - {1'b0, b} - (op == 5'b00011 ? cy : 1'b0);
                // {} keeps ~ at 4/1 bits instead of the 5-bit context
                nib  = a[3:0] + {~b[3:0]} + (op == 5'b00011 ? {~cy} : 1'b1);
                r    = wide[7:0];
                ref_flags = {r[7], r == 8'h00, nib[4], ~^r, wide[8]};
            end
            5'b01111: begin            // INR
                r = a + 8'h01;
                ref_flags = {r[7], r == 8'h00, a[3:0] == 4'hF, ~^r, cy};
            end
            5'b10000: begin            // DCR
                r = a - 8'h01;
                ref_flags = {r[7], r == 8'h00, a[3:0] != 4'h0, ~^r, cy};
            end
            5'b10001: begin            // DAA
                corr = 8'h00;
                if (a[3:0] > 4'd9 || fin[2]) corr = corr + 8'h06;
                if (a > 8'h99 || cy)         corr = corr + 8'h60;
                nib  = a[3:0] + corr[3:0];
                r    = a + corr;
                ref_flags = {r[7], r == 8'h00, nib[4], ~^r, corr[6]};
            end
            5'b10010, 5'b10011: begin  // DADL, DADH
                wide = a + b + (op[0] & cy);
                ref_flags[0] = wide[8];
            end
            5'b00100: begin r = a & b; ref_flags = {r[7], r == 8'h00, 1'b1, ~^r, 1'b0}; end
            5'b00101: begin r = a ^ b; ref_flags = {r[7], r == 8'h00, 1'b0, ~^r, 1'b0}; end
            5'b00110: begin r = a | b; ref_flags = {r[7], r == 8'h00, 1'b0, ~^r, 1'b0}; end
            5'b01000, 5'b01010: ref_flags[0] = a[7];   // RLC, RAL
            5'b01001, 5'b01011: ref_flags[0] = a[0];   // RRC, RAR
            5'b01101: ref_flags[0] = 1'b1;             // STC
            5'b01110: ref_flags[0] = ~cy;              // CMC
            default: ;                                 // CMA, reserved
        endcase
    end
endfunction

// Reference result. CMP returns A - B like SUB; the controller is what
// discards it. Ops that don't write A (STC, CMC, reserved) return A.
function [7:0] ref_result;
    input [7:0] a, b;
    input [4:0] op;
    input [4:0] fin;
    reg         cy;
    reg   [7:0] corr;
    begin
        cy = fin[0];
        case (op)
            5'b00000: ref_result = a + b;
            5'b00001: ref_result = a + b + cy;
            5'b00010: ref_result = a - b;
            5'b00011: ref_result = a - b - cy;
            5'b00100: ref_result = a & b;
            5'b00101: ref_result = a ^ b;
            5'b00110: ref_result = a | b;
            5'b00111: ref_result = a - b;
            5'b01000: ref_result = {a[6:0], a[7]};  // RLC
            5'b01001: ref_result = {a[0], a[7:1]};  // RRC
            5'b01010: ref_result = {a[6:0], cy};    // RAL
            5'b01011: ref_result = {cy, a[7:1]};    // RAR
            5'b01100: ref_result = ~a;              // CMA
            5'b01111: ref_result = a + 8'h01;       // INR
            5'b10000: ref_result = a - 8'h01;       // DCR
            5'b10001: begin                         // DAA
                corr = 8'h00;
                if (a[3:0] > 4'd9 || fin[2]) corr = corr + 8'h06;
                if (a > 8'h99 || cy)         corr = corr + 8'h60;
                ref_result = a + corr;
            end
            5'b10010: ref_result = a + b;           // DADL
            5'b10011: ref_result = a + b + cy;      // DADH
            default:  ref_result = a;               // STC, CMC, reserved
        endcase
    end
endfunction
