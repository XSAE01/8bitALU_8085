//=============================================================================
// Module: alu_8bit
// Description: Complete 8-bit ALU for the Intel 8085 microprocessor.
//              This is the top-level combinational ALU datapath.
//
//              Architecture (matching project block diagram):
//              ┌──────────────────────────────────────────────────────┐
//              │  Accumulator A [7:0]          Temp Reg B [7:0]      │
//              │       │                            │                │
//              │       │              ┌─ XOR gates ─┤ (2's comp)     │
//              │       │              │  2x1 MUX    │                │
//              │       ▼              ▼             ▼                │
//              │  ┌──────────┐  ┌──────────┐  ┌──────────┐          │
//              │  │ 4-bit    │  │ Logic    │  │ Rotate   │          │
//              │  │ ALU High │  │ Unit     │  │ Unit     │          │
//              │  │ [7:4]    │  │          │  │          │          │
//              │  │  ↑ AC    │  │          │  │          │          │
//              │  │ 4-bit    │  │          │  │          │          │
//              │  │ ALU Low  │  │          │  │          │          │
//              │  │ [3:0]    │  │          │  │          │          │
//              │  └────┬─────┘  └────┬─────┘  └────┬─────┘          │
//              │       │             │             │                │
//              │       └──────┬──────┘─────────────┘                │
//              │              ▼                                      │
//              │      Operation Select MUX                           │
//              │              │                                      │
//              │              ▼                                      │
//              │     Flag Generator → [S, Z, AC, P, CY]             │
//              │              │                                      │
//              │              ▼                                      │
//              │        Result [7:0]                                 │
//              └──────────────────────────────────────────────────────┘
//
// ALU Operation encoding (alu_op[3:0]):
//   4'b0000 = ADD   (A + B)
//   4'b0001 = ADC   (A + B + CY)
//   4'b0010 = SUB   (A - B)
//   4'b0011 = SBB   (A - B - CY)
//   4'b0100 = ANA   (A & B)
//   4'b0101 = XRA   (A ^ B)
//   4'b0110 = ORA   (A | B)
//   4'b0111 = CMP   (A - B, result discarded, flags only)
//   4'b1000 = RLC   (Rotate left circular)
//   4'b1001 = RRC   (Rotate right circular)
//   4'b1010 = RAL   (Rotate left through carry)
//   4'b1011 = RAR   (Rotate right through carry)
//   4'b1100 = CMA   (Complement accumulator)
//   4'b1101 = STC   (Set carry flag)
//   4'b1110 = CMC   (Complement carry flag)
//   4'b1111 = INR   (Increment — uses b_in = 0, cin = 1)
//=============================================================================

module alu_8bit (
    input  wire [7:0] a,            // Accumulator A [7:0]
    input  wire [7:0] b,            // Temp Register B [7:0]
    input  wire [3:0] alu_op,       // ALU operation code
    input  wire       carry_flag,   // Current CY flag (for ADC/SBB/RAL/RAR)
    output reg  [7:0] result,       // ALU result [7:0]
    output reg        flag_s,       // Sign flag
    output reg        flag_z,       // Zero flag
    output reg        flag_ac,      // Auxiliary Carry flag
    output reg        flag_p,       // Parity flag
    output reg        flag_cy       // Carry flag
);

    //=========================================================================
    // Internal signals
    //=========================================================================

    // Arithmetic unit signals
    wire [7:0] b_mux;              // B after XOR inversion for subtraction
    wire       arith_cin;          // Carry-in to ALU Low
    wire [7:0] arith_result;       // Arithmetic result from 4-bit ALU slices
    wire       aux_carry_out;      // Carry from Low → High (AC flag)
    wire       carry_out;          // Carry from High (CY flag)
    wire [1:0] arith_op_select;    // Op select for 4-bit ALU slices

    // Logic unit: direct bitwise operations on full 8-bit width
    wire [7:0] and_result;
    wire [7:0] or_result;
    wire [7:0] xor_result;
    wire [7:0] cma_result;

    // Rotate unit signals
    wire [7:0] rotate_result;
    wire       rotate_carry;

    // Flag generator signals
    wire       fg_s, fg_z, fg_ac, fg_p, fg_cy;

    //=========================================================================
    // Subtraction control: B inversion + Carry-in
    //=========================================================================

    // is_subtract: SUB (0010), SBB (0011), CMP (0111)
    wire is_subtract;
    assign is_subtract = (alu_op == 4'b0010) || (alu_op == 4'b0011) || (alu_op == 4'b0111);

    // 2x1 MUX + XOR gates: invert B for subtraction (2's complement)
    assign b_mux = is_subtract ? ~b : b;

    // Carry-in logic:
    //   ADD:  Cin = 0
    //   ADC:  Cin = CY flag
    //   SUB:  Cin = 1 (completes 2's complement)
    //   SBB:  Cin = ~CY flag (borrow = complement of carry for subtraction)
    //   CMP:  Cin = 1 (same as SUB)
    //   INR:  Cin = 1 (increment by 1)
    //   Others: Cin = 0
    reg arith_cin_reg;
    always @(*) begin
        case (alu_op)
            4'b0000: arith_cin_reg = 1'b0;          // ADD: no carry-in
            4'b0001: arith_cin_reg = carry_flag;     // ADC: carry-in = CY
            4'b0010: arith_cin_reg = 1'b1;           // SUB: Cin=1 for 2's comp
            4'b0011: arith_cin_reg = ~carry_flag;    // SBB: Cin = ~CY (borrow)
            4'b0111: arith_cin_reg = 1'b1;           // CMP: same as SUB
            4'b1111: arith_cin_reg = 1'b1;           // INR: increment
            default: arith_cin_reg = 1'b0;
        endcase
    end
    assign arith_cin = arith_cin_reg;

    // For arithmetic operations, the 4-bit ALU slices use op_select = 2'b11 (FA Sum)
    assign arith_op_select = 2'b11;

    //=========================================================================
    // Arithmetic Unit: Two cascaded 4-bit ALU slices
    //=========================================================================

    // 4-bit ALU Low [3:0]
    alu_4bit alu_low (
        .a         (a[3:0]),
        .b         (b_mux[3:0]),
        .cin       (arith_cin),
        .op_select (arith_op_select),
        .result    (arith_result[3:0]),
        .cout      (aux_carry_out)          // This IS the Auxiliary Carry (AC)
    );

    // 4-bit ALU High [7:4]
    alu_4bit alu_high (
        .a         (a[7:4]),
        .b         (b_mux[7:4]),
        .cin       (aux_carry_out),         // Carry chain: Low → High
        .op_select (arith_op_select),
        .result    (arith_result[7:4]),
        .cout      (carry_out)              // This IS the Carry flag (CY)
    );

    //=========================================================================
    // Logic Unit: bitwise operations (AND, OR, XOR, CMA)
    //=========================================================================

    assign and_result = a & b;
    assign or_result  = a | b;
    assign xor_result = a ^ b;
    assign cma_result = ~a;                 // Complement Accumulator

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
    // Flag Generator (for the selected result)
    //=========================================================================

    // We compute flags on the arithmetic result; they get overridden
    // for logic/rotate/special ops below
    flag_generator flag_gen (
        .result    (arith_result),
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
        // Defaults
        result  = 8'h00;
        flag_s  = fg_s;
        flag_z  = fg_z;
        flag_ac = fg_ac;
        flag_p  = fg_p;
        flag_cy = fg_cy;

        case (alu_op)
            // --- Arithmetic operations ---
            4'b0000: begin  // ADD
                result  = arith_result;
            end

            4'b0001: begin  // ADC
                result  = arith_result;
            end

            4'b0010: begin  // SUB
                result  = arith_result;
            end

            4'b0011: begin  // SBB
                result  = arith_result;
            end

            4'b0111: begin  // CMP (same as SUB but result is discarded externally)
                result  = arith_result;
            end

            4'b1111: begin  // INR (increment; CY is NOT affected)
                result  = arith_result;
                flag_cy = carry_flag;       // CY unchanged for INR
            end

            // --- Logical operations ---
            4'b0100: begin  // ANA (AND)
                result  = and_result;
                flag_s  = and_result[7];
                flag_z  = (and_result == 8'h00);
                flag_ac = 1'b1;             // AC is set to 1 for ANA
                flag_p  = ~(^and_result);
                flag_cy = 1'b0;             // CY reset
            end

            4'b0101: begin  // XRA (XOR)
                result  = xor_result;
                flag_s  = xor_result[7];
                flag_z  = (xor_result == 8'h00);
                flag_ac = 1'b0;             // AC reset
                flag_p  = ~(^xor_result);
                flag_cy = 1'b0;             // CY reset
            end

            4'b0110: begin  // ORA (OR)
                result  = or_result;
                flag_s  = or_result[7];
                flag_z  = (or_result == 8'h00);
                flag_ac = 1'b0;             // AC reset
                flag_p  = ~(^or_result);
                flag_cy = 1'b0;             // CY reset
            end

            // --- Rotate operations (only CY affected) ---
            4'b1000: begin  // RLC
                result  = rotate_result;
                flag_s  = carry_flag ? fg_s : fg_s;  // S,Z,AC,P unchanged
                flag_z  = carry_flag ? fg_z : fg_z;  // (preserve current flags)
                flag_cy = rotate_carry;
            end

            4'b1001: begin  // RRC
                result  = rotate_result;
                flag_cy = rotate_carry;
            end

            4'b1010: begin  // RAL
                result  = rotate_result;
                flag_cy = rotate_carry;
            end

            4'b1011: begin  // RAR
                result  = rotate_result;
                flag_cy = rotate_carry;
            end

            // --- Special operations ---
            4'b1100: begin  // CMA (complement accumulator; no flags affected)
                result  = cma_result;
                flag_s  = fg_s;     // Flags unchanged — will be overridden
                flag_z  = fg_z;     // by the top module preserving old flags
                flag_ac = fg_ac;
                flag_p  = fg_p;
                flag_cy = carry_flag;
            end

            4'b1101: begin  // STC (set carry)
                result  = a;        // Accumulator unchanged
                flag_cy = 1'b1;
            end

            4'b1110: begin  // CMC (complement carry)
                result  = a;        // Accumulator unchanged
                flag_cy = ~carry_flag;
            end

            default: begin
                result  = 8'h00;
                flag_cy = carry_flag;
            end
        endcase
    end

endmodule
