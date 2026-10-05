//=============================================================================
// Module: alu_8bit
// Description: Complete 8-bit ALU for the Intel 8085 microprocessor.
//              This is the top-level combinational ALU datapath.
//
//              Architecture (see docs/alu_8bit_architecture.svg):
//
//              A[7:0]                     B[7:0]
//                │                          │
//                │                ┌─────────▼──────────┐
//                │                │ B Operand Select   │  B / ~B / 00h / FFh / DAA corr
//                │                └─────────┬──────────┘
//                │                          │ B'[7:0]
//                ▼                          ▼
//              ┌──────────────────────────────────────┐
//              │ 4-bit ALU High [7:4]  (4 × 1-bit)    │──► Cout → CY
//              │            ▲ AC (Low Cout)            │
//              │ 4-bit ALU Low  [3:0]  (4 × 1-bit)    │◄── Cin (Carry-in logic)
//              └──────────────────┬───────────────────┘
//                                 │ slice_result     ┌──────────────┐
//                                 │                  │ Rotate Unit  │◄── A, CY
//                                 │                  └──────┬───────┘
//                                 ▼                         ▼
//                        ┌────────────────────────────────────────┐
//                        │  Result Select: slice / rotate / A     │──► Result[7:0]
//                        └────────────────────────────────────────┘
//              Flag Generator (S, Z, P from slice_result) + per-op AC/CY logic
//              Flags not affected by an operation are passed through from
//              flags_in, so the flag register can be written unconditionally.
//
// ALU Operation encoding (alu_op[4:0]):
//   5'b00000 = ADD   A + B                 all flags
//   5'b00001 = ADC   A + B + CY            all flags
//   5'b00010 = SUB   A - B                 all flags (CY = borrow)
//   5'b00011 = SBB   A - B - CY            all flags (CY = borrow)
//   5'b00100 = ANA   A & B                 S,Z,P; AC=1; CY=0
//   5'b00101 = XRA   A ^ B                 S,Z,P; AC=0; CY=0
//   5'b00110 = ORA   A | B                 S,Z,P; AC=0; CY=0
//   5'b00111 = CMP   A - B (flags only)    all flags (CY = borrow)
//   5'b01000 = RLC   rotate left           CY only
//   5'b01001 = RRC   rotate right          CY only
//   5'b01010 = RAL   rotate left thru CY   CY only
//   5'b01011 = RAR   rotate right thru CY  CY only
//   5'b01100 = CMA   ~A                    no flags
//   5'b01101 = STC   CY = 1                CY only
//   5'b01110 = CMC   CY = ~CY              CY only
//   5'b01111 = INR   A + 1                 S,Z,AC,P; CY unchanged
//   5'b10000 = DCR   A - 1                 S,Z,AC,P; CY unchanged
//   5'b10001 = DAA   decimal adjust A      all flags
//   5'b10010 = DADL  A + B   (DAD low)     CY only
//   5'b10011 = DADH  A + B + CY (DAD high) CY only
//   5'b10100 .. 5'b11111                   reserved: A unchanged, no flags
//
// DAD rp (HL <- HL + rp) is a 16-bit add that the 8085 itself performs as
// two 8-bit ALU passes, which is how it is exposed here:
//   DADL with A = L, B = rp low   →  L' and CY
//   DADH with A = H, B = rp high  →  H' and final CY
//
// AC on subtraction (SUB/SBB/CMP/DCR) is the carry out of the low nibble of
// the two's-complement add A + ~B + ~borrow_in, i.e. NOT a half-borrow.
//=============================================================================

module alu_8bit (
    input  wire [7:0] a,            // Accumulator A [7:0]
    input  wire [7:0] b,            // Temp Register B [7:0]
    input  wire [4:0] alu_op,       // ALU operation code
    input  wire [4:0] flags_in,     // Current flags {S, Z, AC, P, CY}
    output reg  [7:0] result,       // ALU result [7:0]
    output reg        flag_s,       // Sign flag
    output reg        flag_z,       // Zero flag
    output reg        flag_ac,      // Auxiliary Carry flag
    output reg        flag_p,       // Parity flag
    output reg        flag_cy       // Carry flag
);

    //=========================================================================
    // Operation codes
    //=========================================================================
    localparam [4:0] OP_ADD  = 5'b00000,
                     OP_ADC  = 5'b00001,
                     OP_SUB  = 5'b00010,
                     OP_SBB  = 5'b00011,
                     OP_ANA  = 5'b00100,
                     OP_XRA  = 5'b00101,
                     OP_ORA  = 5'b00110,
                     OP_CMP  = 5'b00111,
                     OP_RLC  = 5'b01000,
                     OP_RRC  = 5'b01001,
                     OP_RAL  = 5'b01010,
                     OP_RAR  = 5'b01011,
                     OP_CMA  = 5'b01100,
                     OP_STC  = 5'b01101,
                     OP_CMC  = 5'b01110,
                     OP_INR  = 5'b01111,
                     OP_DCR  = 5'b10000,
                     OP_DAA  = 5'b10001,
                     OP_DADL = 5'b10010,
                     OP_DADH = 5'b10011;

    // 1-bit slice op_select encoding
    localparam [1:0] SEL_AND   = 2'b00,
                     SEL_OR    = 2'b01,
                     SEL_XOR   = 2'b10,
                     SEL_ARITH = 2'b11;

    //=========================================================================
    // Internal signals
    //=========================================================================

    wire       carry_flag = flags_in[0];   // Current CY flag
    wire       aux_flag   = flags_in[2];   // Current AC flag (for DAA)

    // DAA correction: +06h if the low digit is invalid or AC is set,
    // +60h if the whole byte is above 99h or CY is set (which also sets CY)
    wire       daa_lo   = (a[3:0] > 4'd9) | aux_flag;
    wire       daa_hi   = (a > 8'h99)     | carry_flag;
    wire [7:0] daa_corr = {1'b0, daa_hi, daa_hi, 1'b0, 1'b0, daa_lo, daa_lo, 1'b0};

    reg  [7:0] b_operand;          // B after operand select (B / ~B / 00h / FFh)
    reg        slice_cin;          // Carry-in to ALU Low
    reg  [1:0] slice_op_select;    // Op select for all 8 bit-slices
    wire [7:0] slice_result;       // Result from the two 4-bit ALU slices
    wire       aux_carry_out;      // Carry from Low → High (AC flag)
    wire       carry_out;          // Carry from High (CY before borrow fix-up)

    // Rotate unit signals
    wire [7:0] rotate_result;
    wire       rotate_carry;

    // Flag generator signals
    wire       fg_s, fg_z, fg_ac, fg_p, fg_cy;

    //=========================================================================
    // Slice control: B operand select, carry-in, op_select
    //=========================================================================
    //   ADD/ADC     : B,   Cin = 0 / CY,      FA sum
    //   SUB/CMP     : ~B,  Cin = 1,           FA sum  (A + ~B + 1 = A - B)
    //   SBB         : ~B,  Cin = ~CY,         FA sum  (A + ~B + ~CY = A - B - CY)
    //   INR         : 00h, Cin = 1,           FA sum  (A + 0 + 1)
    //   DCR         : FFh, Cin = 0,           FA sum  (A + FFh = A - 1)
    //   DAA         : 00h/06h/60h/66h, Cin=0, FA sum  (A + correction)
    //   DADL / DADH : B,   Cin = 0 / CY,      FA sum  (same as ADD / ADC)
    //   ANA/ORA/XRA : B,   Cin = 0,           AND / OR / XOR
    //   CMA         : FFh, Cin = 0,           XOR     (A ^ FFh = ~A)
    //   Others      : B,   Cin = 0,           FA sum  (slice output unused)
    always @(*) begin
        b_operand       = b;
        slice_cin       = 1'b0;
        slice_op_select = SEL_ARITH;

        case (alu_op)
            OP_ADD: ;
            OP_ADC: slice_cin = carry_flag;
            OP_SUB: begin b_operand = ~b; slice_cin = 1'b1;        end
            OP_SBB: begin b_operand = ~b; slice_cin = ~carry_flag; end
            OP_CMP: begin b_operand = ~b; slice_cin = 1'b1;        end
            OP_INR: begin b_operand = 8'h00; slice_cin = 1'b1;     end
            OP_DCR: b_operand = 8'hFF;
            OP_DAA: b_operand = daa_corr;
            OP_DADL: ;
            OP_DADH: slice_cin = carry_flag;
            OP_ANA: slice_op_select = SEL_AND;
            OP_ORA: slice_op_select = SEL_OR;
            OP_XRA: slice_op_select = SEL_XOR;
            OP_CMA: begin b_operand = 8'hFF; slice_op_select = SEL_XOR; end
            default: ;
        endcase
    end

    //=========================================================================
    // Bit-slice datapath: two cascaded 4-bit ALU slices
    //=========================================================================

    // 4-bit ALU Low [3:0]
    alu_4bit alu_low (
        .a         (a[3:0]),
        .b         (b_operand[3:0]),
        .cin       (slice_cin),
        .op_select (slice_op_select),
        .result    (slice_result[3:0]),
        .cout      (aux_carry_out)          // This IS the Auxiliary Carry (AC)
    );

    // 4-bit ALU High [7:4]
    alu_4bit alu_high (
        .a         (a[7:4]),
        .b         (b_operand[7:4]),
        .cin       (aux_carry_out),         // Carry chain: Low → High
        .op_select (slice_op_select),
        .result    (slice_result[7:4]),
        .cout      (carry_out)              // Carry out of bit 7
    );

    //=========================================================================
    // Rotate Unit
    //=========================================================================

    rotate_unit rot_unit (
        .a          (a),
        .carry_in   (carry_flag),
        .rot_select (alu_op[1:0]),          // Low 2 bits select rotation type
        .result     (rotate_result),
        .carry_out  (rotate_carry)
    );

    //=========================================================================
    // Flag Generator (S, Z, P from the slice result; AC/CY from the carries)
    //=========================================================================

    flag_generator flag_gen (
        .result    (slice_result),
        .carry_out (carry_out),
        .aux_carry (aux_carry_out),
        .flag_s    (fg_s),
        .flag_z    (fg_z),
        .flag_ac   (fg_ac),
        .flag_p    (fg_p),
        .flag_cy   (fg_cy)
    );

    //=========================================================================
    // Operation Select MUX + Flag assignment
    //=========================================================================

    always @(*) begin
        // Defaults: result = A, every flag unchanged (also reserved ops)
        result = a;
        {flag_s, flag_z, flag_ac, flag_p, flag_cy} = flags_in;

        case (alu_op)
            // --- Addition: all flags ---
            OP_ADD, OP_ADC: begin
                result = slice_result;
                {flag_s, flag_z, flag_ac, flag_p, flag_cy} = {fg_s, fg_z, fg_ac, fg_p, fg_cy};
            end

            // --- Subtraction: all flags, CY = borrow = ~carry-out ---
            OP_SUB, OP_SBB, OP_CMP: begin
                result = slice_result;          // CMP: discarded by the controller
                {flag_s, flag_z, flag_ac, flag_p, flag_cy} = {fg_s, fg_z, fg_ac, fg_p, ~fg_cy};
            end

            // --- Increment / decrement: CY not affected ---
            OP_INR, OP_DCR: begin
                result = slice_result;
                {flag_s, flag_z, flag_ac, flag_p} = {fg_s, fg_z, fg_ac, fg_p};
            end

            // --- Decimal adjust: AC from the low-digit correction carry,
            //     CY set by the high-digit correction (never cleared) ---
            OP_DAA: begin
                result = slice_result;
                {flag_s, flag_z, flag_ac, flag_p, flag_cy} = {fg_s, fg_z, fg_ac, fg_p, daa_hi};
            end

            // --- DAD halves: only CY affected ---
            OP_DADL, OP_DADH: begin
                result  = slice_result;
                flag_cy = fg_cy;
            end

            // --- Logical: S, Z, P from result; AC fixed; CY reset ---
            OP_ANA: begin
                result = slice_result;
                {flag_s, flag_z, flag_ac, flag_p, flag_cy} = {fg_s, fg_z, 1'b1, fg_p, 1'b0};
            end

            OP_XRA, OP_ORA: begin
                result = slice_result;
                {flag_s, flag_z, flag_ac, flag_p, flag_cy} = {fg_s, fg_z, 1'b0, fg_p, 1'b0};
            end

            // --- Rotate: only CY affected ---
            OP_RLC, OP_RRC, OP_RAL, OP_RAR: begin
                result  = rotate_result;
                flag_cy = rotate_carry;
            end

            // --- Complement accumulator: no flags affected ---
            OP_CMA: result = slice_result;

            // --- Carry flag operations: A unchanged ---
            OP_STC: flag_cy = 1'b1;
            OP_CMC: flag_cy = ~carry_flag;

            default: ;
        endcase
    end

endmodule
