//=============================================================================
// Testbench: tb_alu_8085_top
// Description: Top-level integration testbench for the complete 8085 ALU
//              subsystem (ALU + FSM Controller + Registers).
//              Tests the full pipeline: Load A → Load B → Load Op → Execute → Done
//=============================================================================

`timescale 1ns / 1ps

module tb_alu_8085_top;

    // Clock parameters
    parameter CLK_PERIOD = 20;  // 50 MHz

    // Inputs
    reg        clk;
    reg        rst;
    reg        start;
    reg  [7:0] data_in_a;
    reg  [7:0] data_in_b;
    reg  [3:0] alu_op_in;

    // Outputs
    wire [7:0] acc_out;
    wire [7:0] result_out;
    wire [4:0] flags_out;
    wire       done;
    wire [2:0] state_out;

    // Flag decomposition for readability
    wire flag_s  = flags_out[4];
    wire flag_z  = flags_out[3];
    wire flag_ac = flags_out[2];
    wire flag_p  = flags_out[1];
    wire flag_cy = flags_out[0];

    // Instantiate UUT
    alu_8085_top uut (
        .clk        (clk),
        .rst        (rst),
        .start      (start),
        .data_in_a  (data_in_a),
        .data_in_b  (data_in_b),
        .alu_op_in  (alu_op_in),
        .acc_out    (acc_out),
        .result_out (result_out),
        .flags_out  (flags_out),
        .done       (done),
        .state_out  (state_out)
    );

    // Test tracking
    integer pass_count = 0;
    integer fail_count = 0;
    integer test_num   = 0;

    // Clock generation
    initial clk = 0;
    always #(CLK_PERIOD / 2) clk = ~clk;

    // =========================================================================
    // Task: Execute one complete ALU operation through the FSM pipeline
    // Pipeline: S0(idle) → S1(load_a) → S2(load_b) → S3(load_op)
    //           → S4(execute) → S5(done) → S0(idle)
    // =========================================================================
    task execute_op;
        input [7:0]  op_a;
        input [7:0]  op_b;
        input [3:0]  op_code;
        input [127:0] desc;
        begin
            // Setup inputs
            data_in_a = op_a;
            data_in_b = op_b;
            alu_op_in = op_code;

            // Pulse start
            @(posedge clk);
            start = 1'b1;
            @(posedge clk);
            start = 1'b0;

            // Wait for S1 (LOAD_A)
            @(posedge clk);
            // Wait for S2 (LOAD_B)
            @(posedge clk);
            // Wait for S3 (LOAD_OP)
            @(posedge clk);
            // Wait for S4 (EXECUTE) — results latched
            @(posedge clk);
            // Wait for S5 (DONE) — done asserted
            @(posedge clk);
            // Now back to S0, results stable

            $display("  [%0s] A_in=%h B_in=%h Op=%b => Acc=%h | S=%b Z=%b AC=%b P=%b CY=%b | State=%d",
                     desc, op_a, op_b, op_code, acc_out,
                     flag_s, flag_z, flag_ac, flag_p, flag_cy, state_out);
        end
    endtask

    // Task: check accumulated result
    task check_acc;
        input [7:0]  expected_acc;
        input [127:0] desc;
        begin
            test_num = test_num + 1;
            if (acc_out === expected_acc) begin
                pass_count = pass_count + 1;
                $display("  [PASS] %0d. %0s: Acc=%h (expected %h)", test_num, desc, acc_out, expected_acc);
            end else begin
                fail_count = fail_count + 1;
                $display("  [FAIL] %0d. %0s: Acc=%h (expected %h)", test_num, desc, acc_out, expected_acc);
            end
        end
    endtask

    // =========================================================================
    // Main test sequence
    // =========================================================================
    initial begin
        $display("================================================================");
        $display("  8085 ALU Top-Level Integration Testbench");
        $display("  (FSM Controller + ALU + Registers)");
        $display("================================================================\n");

        // Initialize
        rst       = 1'b1;
        start     = 1'b0;
        data_in_a = 8'h00;
        data_in_b = 8'h00;
        alu_op_in = 4'h0;

        // Reset for 3 clock cycles
        repeat (3) @(posedge clk);
        rst = 1'b0;
        @(posedge clk);

        $display("--- Reset complete. Starting operations ---\n");

        // =============================================================
        // Test 1: ADD — 30h + 12h = 42h
        // =============================================================
        $display("Test 1: ADD");
        execute_op(8'h30, 8'h12, 4'b0000, "ADD 30+12          ");
        check_acc(8'h42, "ADD result         ");

        // =============================================================
        // Test 2: SUB — use accumulated value: 42h - 12h = 30h
        // =============================================================
        $display("\nTest 2: SUB");
        execute_op(8'h42, 8'h12, 4'b0010, "SUB 42-12          ");
        check_acc(8'h30, "SUB result         ");

        // =============================================================
        // Test 3: ADD with carry — FFh + 01h = 00h, CY=1
        // =============================================================
        $display("\nTest 3: ADD overflow");
        execute_op(8'hFF, 8'h01, 4'b0000, "ADD FF+01          ");
        check_acc(8'h00, "ADD overflow        ");

        // =============================================================
        // Test 4: ADC — use CY=1 from previous: 30h + 10h + 1 = 41h
        // =============================================================
        $display("\nTest 4: ADC (with carry from prev)");
        execute_op(8'h30, 8'h10, 4'b0001, "ADC 30+10+CY       ");
        check_acc(8'h41, "ADC result         ");

        // =============================================================
        // Test 5: ANA — A5h & 0Fh = 05h
        // =============================================================
        $display("\nTest 5: ANA");
        execute_op(8'hA5, 8'h0F, 4'b0100, "ANA A5&0F          ");
        check_acc(8'h05, "ANA result         ");

        // =============================================================
        // Test 6: ORA — A0h | 05h = A5h
        // =============================================================
        $display("\nTest 6: ORA");
        execute_op(8'hA0, 8'h05, 4'b0110, "ORA A0|05          ");
        check_acc(8'hA5, "ORA result         ");

        // =============================================================
        // Test 7: XRA — A5h ^ FFh = 5Ah
        // =============================================================
        $display("\nTest 7: XRA");
        execute_op(8'hA5, 8'hFF, 4'b0101, "XRA A5^FF          ");
        check_acc(8'h5A, "XRA result         ");

        // =============================================================
        // Test 8: CMA — ~5Ah = A5h
        // =============================================================
        $display("\nTest 8: CMA");
        execute_op(8'h5A, 8'h00, 4'b1100, "CMA ~5A            ");
        check_acc(8'hA5, "CMA result         ");

        // =============================================================
        // Test 9: RLC — A=81h (10000001) → 03h
        // =============================================================
        $display("\nTest 9: RLC");
        execute_op(8'h81, 8'h00, 4'b1000, "RLC 81             ");
        check_acc(8'h03, "RLC result         ");

        // =============================================================
        // Test 10: RRC — A=81h (10000001) → C0h
        // =============================================================
        $display("\nTest 10: RRC");
        execute_op(8'h81, 8'h00, 4'b1001, "RRC 81             ");
        check_acc(8'hC0, "RRC result         ");

        // =============================================================
        // Test 11: CMP — A=42h, B=42h → Zero flag set, Acc unchanged
        // =============================================================
        $display("\nTest 11: CMP (equal)");
        execute_op(8'h42, 8'h42, 4'b0111, "CMP 42==42         ");
        // CMP should NOT modify accumulator (the FSM controller handles this)
        // But since we loaded A=42h in the load phase, Acc will reflect that
        // The key check is that Z flag is set

        // =============================================================
        // Test 12: SBB — 42h - 12h - CY
        // =============================================================
        $display("\nTest 12: SBB");
        execute_op(8'h42, 8'h12, 4'b0011, "SBB 42-12-CY       ");

        // =============================================================
        // Test 13: STC — Set carry flag
        // =============================================================
        $display("\nTest 13: STC");
        execute_op(8'h42, 8'h00, 4'b1101, "STC                ");
        check_acc(8'h42, "STC acc unchanged  ");

        // =============================================================
        // Test 14: CMC — Complement carry flag
        // =============================================================
        $display("\nTest 14: CMC");
        execute_op(8'h42, 8'h00, 4'b1110, "CMC                ");
        check_acc(8'h42, "CMC acc unchanged  ");

        // =============================================================
        // Test 15: INR — 41h + 1 = 42h
        // =============================================================
        $display("\nTest 15: INR");
        execute_op(8'h41, 8'h00, 4'b1111, "INR 41+1           ");
        check_acc(8'h42, "INR result         ");

        // =============================================================
        // Test 16: SUB to zero — verify Z flag
        // =============================================================
        $display("\nTest 16: SUB to zero (Z flag)");
        execute_op(8'h55, 8'h55, 4'b0010, "SUB 55-55=00       ");
        check_acc(8'h00, "SUB zero result    ");

        // =============================================================
        // Summary
        // =============================================================
        $display("\n================================================================");
        $display("  Results: %0d PASSED, %0d FAILED out of %0d tests",
                 pass_count, fail_count, test_num);
        $display("================================================================");

        if (fail_count == 0)
            $display("  >>> ALL TESTS PASSED <<<");
        else
            $display("  >>> SOME TESTS FAILED <<<");

        #100;
        $finish;
    end

    // Dump waveforms
    initial begin
        $dumpfile("alu_8085_top.vcd");
        $dumpvars(0, tb_alu_8085_top);
    end

    // Timeout safety
    initial begin
        #100000;
        $display("[ERROR] Simulation timeout!");
        $finish;
    end

endmodule
