//=============================================================================
// Module: fsm_controller
// Description: FSM-based controller for the 8085 ALU.
//              Sequences the ALU through Load → Execute → Done phases.
//
//              State diagram (see docs/fsm_controller.svg):
//
//              S0 (IDLE/RESET) ──start──► S1 (LOAD_A)
//              S1 (LOAD_A)     ──────────► S2 (LOAD_B)
//              S2 (LOAD_B)     ──────────► S3 (LOAD_OP)
//              S3 (LOAD_OP)    ──────────► S4 (EXECUTE)
//              S4 (EXECUTE)    ──────────► S5 (DONE)
//              S5 (DONE)       ──────────► S0 (IDLE)
//
// Control outputs generated per state:
//   - load_a   : Load Accumulator register
//   - load_b   : Load Temp register B
//   - load_op  : Latch the ALU operation code
//   - done     : Result is valid, flags updated
//   - acc_wr   : Write result back to Accumulator (all ops except CMP)
//   - flag_wr  : Write new flags to Flag Register (every op; the ALU passes
//                through any flag the operation does not affect)
//
// alu_op is the opcode latched in S3 (not the raw input), so the write-back
// decision in S4 always matches the operation the ALU is executing.
//=============================================================================

module fsm_controller (
    input  wire       clk,          // System clock
    input  wire       rst,          // Synchronous reset (active high)
    input  wire       start,        // Start operation
    input  wire [4:0] alu_op,       // Latched ALU operation (from S3)
    output reg        load_a,       // Load Accumulator
    output reg        load_b,       // Load Temp Reg B
    output reg        load_op,      // Latch ALU operation
    output reg        done,         // Operation complete
    output reg        acc_wr,       // Write-back to Accumulator
    output reg        flag_wr,      // Write-back to Flag Register
    output reg  [2:0] state_out     // Current state (for debug)
);

    //=========================================================================
    // State encoding
    //=========================================================================
    localparam [2:0] S0_IDLE    = 3'd0,   // Idle / Reset
                     S1_LOAD_A  = 3'd1,   // Load Accumulator
                     S2_LOAD_B  = 3'd2,   // Load Temp Register B
                     S3_LOAD_OP = 3'd3,   // Load operation code
                     S4_EXECUTE = 3'd4,   // Execute ALU operation
                     S5_DONE    = 3'd5;   // Latch result, assert done

    reg [2:0] current_state, next_state;

    //=========================================================================
    // State register (sequential)
    //=========================================================================
    always @(posedge clk) begin
        if (rst)
            current_state <= S0_IDLE;
        else
            current_state <= next_state;
    end

    //=========================================================================
    // Next state logic (combinational)
    //=========================================================================
    always @(*) begin
        next_state = current_state;  // Default: hold state

        case (current_state)
            S0_IDLE: begin
                if (start)
                    next_state = S1_LOAD_A;
            end

            S1_LOAD_A:
                next_state = S2_LOAD_B;

            S2_LOAD_B:
                next_state = S3_LOAD_OP;

            S3_LOAD_OP:
                next_state = S4_EXECUTE;

            S4_EXECUTE:
                next_state = S5_DONE;

            S5_DONE:
                next_state = S0_IDLE;

            default:
                next_state = S0_IDLE;
        endcase
    end

    //=========================================================================
    // Output logic (combinational)
    //=========================================================================

    // CMP only updates flags; every other operation writes the Accumulator
    wire is_cmp;
    assign is_cmp = (alu_op == 5'b00111);

    always @(*) begin
        // Defaults: all signals deasserted
        load_a    = 1'b0;
        load_b    = 1'b0;
        load_op   = 1'b0;
        done      = 1'b0;
        acc_wr    = 1'b0;
        flag_wr   = 1'b0;
        state_out = current_state;

        case (current_state)
            S0_IDLE: begin
                // Waiting for start signal
            end

            S1_LOAD_A: begin
                load_a = 1'b1;      // Load Accumulator from data bus
            end

            S2_LOAD_B: begin
                load_b = 1'b1;      // Load Temp Register B from data bus
            end

            S3_LOAD_OP: begin
                load_op = 1'b1;     // Latch the ALU operation code
            end

            S4_EXECUTE: begin
                acc_wr  = ~is_cmp;  // CMP doesn't write result to Acc
                flag_wr = 1'b1;     // Unaffected flags are passed through
            end

            S5_DONE: begin
                done = 1'b1;        // Signal completion
            end

            default: begin
                // Safe defaults
            end
        endcase
    end

endmodule
