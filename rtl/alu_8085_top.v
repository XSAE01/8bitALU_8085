//=============================================================================
// Module: alu_8085_top
// Description: Top-level module integrating the 8-bit ALU with the FSM
//              controller, Accumulator register, Temp register, and Flag
//              register — the complete 8085 ALU subsystem.
//
//              ┌──────────────────────────────────────────────────────┐
//              │                    alu_8085_top                      │
//              │                                                      │
//              │  ┌──────────────┐         ┌──────────────┐          │
//              │  │ FSM          │ control │              │          │
//              │  │ Controller   │────────►│   8-bit ALU  │          │
//              │  │ (S0→S5)      │         │  (alu_8bit)  │          │
//              │  │              │◄────────│              │          │
//              │  └──────────────┘  flags  └──────┬───────┘          │
//              │                                   │                  │
//              │  ┌────────────┐  ┌────────────┐  │                  │
//              │  │ Acc Reg    │  │ Flag Reg   │◄─┘                  │
//              │  │ A [7:0]   │  │ S,Z,AC,P,CY│                     │
//              │  └────────────┘  └────────────┘                     │
//              └──────────────────────────────────────────────────────┘
//=============================================================================

module alu_8085_top (
    input  wire       clk,          // System clock
    input  wire       rst,          // Synchronous reset (active high)
    input  wire       start,        // Start ALU operation
    input  wire [7:0] data_in_a,    // Data input for Accumulator
    input  wire [7:0] data_in_b,    // Data input for Temp Register B
    input  wire [3:0] alu_op_in,    // ALU operation code
    output wire [7:0] acc_out,      // Accumulator output
    output wire [7:0] result_out,   // ALU result (direct)
    output wire [4:0] flags_out,    // Flags: {S, Z, AC, P, CY}
    output wire       done,         // Operation complete
    output wire [2:0] state_out     // FSM state (for debug)
);

    //=========================================================================
    // Internal signals
    //=========================================================================

    // FSM control signals
    wire        ctrl_load_a;
    wire        ctrl_load_b;
    wire        ctrl_load_op;
    wire        ctrl_execute;
    wire        ctrl_done;
    wire        ctrl_acc_wr;
    wire        ctrl_flag_wr;

    // Registered operands and opcode
    reg  [7:0]  acc_reg;            // Accumulator register
    reg  [7:0]  temp_b_reg;         // Temp register B
    reg  [3:0]  alu_op_reg;         // Latched ALU operation

    // Flag register
    reg         flag_s_reg;         // Sign
    reg         flag_z_reg;         // Zero
    reg         flag_ac_reg;        // Auxiliary Carry
    reg         flag_p_reg;         // Parity
    reg         flag_cy_reg;        // Carry

    // ALU outputs (combinational)
    wire [7:0]  alu_result;
    wire        alu_flag_s;
    wire        alu_flag_z;
    wire        alu_flag_ac;
    wire        alu_flag_p;
    wire        alu_flag_cy;

    //=========================================================================
    // FSM Controller instantiation
    //=========================================================================

    fsm_controller fsm_inst (
        .clk       (clk),
        .rst       (rst),
        .start     (start),
        .alu_op_in (alu_op_in),
        .load_a    (ctrl_load_a),
        .load_b    (ctrl_load_b),
        .load_op   (ctrl_load_op),
        .execute   (ctrl_execute),
        .done      (ctrl_done),
        .acc_wr    (ctrl_acc_wr),
        .flag_wr   (ctrl_flag_wr),
        .state_out (state_out)
    );

    //=========================================================================
    // 8-bit ALU instantiation
    //=========================================================================

    alu_8bit alu_inst (
        .a          (acc_reg),
        .b          (temp_b_reg),
        .alu_op     (alu_op_reg),
        .carry_flag (flag_cy_reg),
        .result     (alu_result),
        .flag_s     (alu_flag_s),
        .flag_z     (alu_flag_z),
        .flag_ac    (alu_flag_ac),
        .flag_p     (alu_flag_p),
        .flag_cy    (alu_flag_cy)
    );

    //=========================================================================
    // Register file: Accumulator, Temp B, ALU Op, Flags
    //=========================================================================

    always @(posedge clk) begin
        if (rst) begin
            acc_reg     <= 8'h00;
            temp_b_reg  <= 8'h00;
            alu_op_reg  <= 4'h0;
            flag_s_reg  <= 1'b0;
            flag_z_reg  <= 1'b1;    // Zero flag set on reset (acc = 0)
            flag_ac_reg <= 1'b0;
            flag_p_reg  <= 1'b1;    // Even parity of 0 = set
            flag_cy_reg <= 1'b0;
        end else begin
            // Load Accumulator
            if (ctrl_load_a)
                acc_reg <= data_in_a;

            // Load Temp Register B
            if (ctrl_load_b)
                temp_b_reg <= data_in_b;

            // Latch ALU operation code
            if (ctrl_load_op)
                alu_op_reg <= alu_op_in;

            // Write ALU result back to Accumulator
            if (ctrl_acc_wr)
                acc_reg <= alu_result;

            // Update Flag Register
            if (ctrl_flag_wr) begin
                flag_s_reg  <= alu_flag_s;
                flag_z_reg  <= alu_flag_z;
                flag_ac_reg <= alu_flag_ac;
                flag_p_reg  <= alu_flag_p;
                flag_cy_reg <= alu_flag_cy;
            end
        end
    end

    //=========================================================================
    // Output assignments
    //=========================================================================

    assign acc_out    = acc_reg;
    assign result_out = alu_result;
    assign flags_out  = {flag_s_reg, flag_z_reg, flag_ac_reg, flag_p_reg, flag_cy_reg};
    assign done       = ctrl_done;

endmodule
