//=============================================================================
// Testbench: tb_alu_4bit
// Description: Tests the 4-bit ALU slice with arithmetic and logic operations.
//              Directed tests followed by an exhaustive sweep of every
//              {op_select, A, B, Cin} combination (4 × 16 × 16 × 2 = 2048).
//              Cout is only checked in arithmetic mode (op_select = 11); in
//              logic modes it is the unused Full Adder carry.
//=============================================================================

`timescale 1ns / 1ps

module tb_alu_4bit;

    // Inputs
    reg  [3:0] a, b;
    reg        cin;
    reg  [1:0] op_select;

    // Outputs
    wire [3:0] result;
    wire       cout;

    // Instantiate UUT
    alu_4bit uut (
        .a         (a),
        .b         (b),
        .cin       (cin),
        .op_select (op_select),
        .result    (result),
        .cout      (cout)
    );

    // Test tracking
    integer pass_count = 0;
    integer fail_count = 0;
    integer test_num   = 0;

    // Task: check 4-bit result and carry-out (arithmetic mode)
    task check_arith;
        input [3:0]    exp_result;
        input          exp_cout;
        input [8*8-1:0] test_name;
        begin
            test_num = test_num + 1;
            if (result === exp_result && cout === exp_cout) begin
                pass_count = pass_count + 1;
                $display("[PASS] Test %0d (%0s): A=%h B=%h Cin=%b OpSel=%b => Result=%h Cout=%b",
                         test_num, test_name, a, b, cin, op_select, result, cout);
            end else begin
                fail_count = fail_count + 1;
                $display("[FAIL] Test %0d (%0s): A=%h B=%h Cin=%b OpSel=%b => Result=%h Cout=%b (Expected %h, %b)",
                         test_num, test_name, a, b, cin, op_select, result, cout, exp_result, exp_cout);
            end
        end
    endtask

    // Task: check 4-bit result only (logic mode; Cout is don't-care)
    task check_logic;
        input [3:0]    exp_result;
        input [8*8-1:0] test_name;
        begin
            test_num = test_num + 1;
            if (result === exp_result) begin
                pass_count = pass_count + 1;
                $display("[PASS] Test %0d (%0s): A=%h B=%h OpSel=%b => Result=%h",
                         test_num, test_name, a, b, op_select, result);
            end else begin
                fail_count = fail_count + 1;
                $display("[FAIL] Test %0d (%0s): A=%h B=%h OpSel=%b => Result=%h (Expected %h)",
                         test_num, test_name, a, b, op_select, result, exp_result);
            end
        end
    endtask

    // Exhaustive sweep variables
    integer i_op, i_a, i_b, i_c;
    integer sweep_fail;
    reg [4:0] exp5;
    reg [3:0] exp4;

    initial begin
        $display("==============================================");
        $display("  4-bit ALU Slice Testbench");
        $display("==============================================\n");

        // ===================== ARITHMETIC MODE (op_select = 2'b11) =====================
        $display("--- Arithmetic Operations (op_select=11) ---");
        op_select = 2'b11;

        // ADD: 3 + 2 = 5, no carry
        a = 4'h3; b = 4'h2; cin = 0; #10;
        check_arith(4'h5, 1'b0, "ADD");

        // ADD: 8 + 9 = 17 = 1 (carry)
        a = 4'h8; b = 4'h9; cin = 0; #10;
        check_arith(4'h1, 1'b1, "ADD+CY");

        // ADD with Cin: 5 + 3 + 1 = 9
        a = 4'h5; b = 4'h3; cin = 1; #10;
        check_arith(4'h9, 1'b0, "ADC");

        // ADD: F + 1 = 0 (carry)
        a = 4'hF; b = 4'h1; cin = 0; #10;
        check_arith(4'h0, 1'b1, "ADD OVR");

        // ADD: F + F + 1 = 1F (carry, result=F)
        a = 4'hF; b = 4'hF; cin = 1; #10;
        check_arith(4'hF, 1'b1, "ADC MAX");

        // ===================== LOGIC MODE: AND (op_select = 2'b00) =====================
        $display("\n--- AND Operations (op_select=00) ---");
        op_select = 2'b00;

        a = 4'hF; b = 4'hA; cin = 0; #10;
        check_logic(4'hA, "AND");

        a = 4'h5; b = 4'h3; cin = 0; #10;
        check_logic(4'h1, "AND");

        // ===================== LOGIC MODE: OR (op_select = 2'b01) =====================
        $display("\n--- OR Operations (op_select=01) ---");
        op_select = 2'b01;

        a = 4'h5; b = 4'h3; cin = 0; #10;
        check_logic(4'h7, "OR");

        a = 4'h0; b = 4'h0; cin = 0; #10;
        check_logic(4'h0, "OR ZERO");

        // ===================== LOGIC MODE: XOR (op_select = 2'b10) =====================
        $display("\n--- XOR Operations (op_select=10) ---");
        op_select = 2'b10;

        a = 4'hF; b = 4'hA; cin = 0; #10;
        check_logic(4'h5, "XOR");

        a = 4'h5; b = 4'h5; cin = 0; #10;
        check_logic(4'h0, "XOR EQ");

        // ===================== EXHAUSTIVE SWEEP =====================
        $display("\n--- Exhaustive sweep (2048 combinations) ---");
        sweep_fail = 0;
        for (i_op = 0; i_op < 4; i_op = i_op + 1)
            for (i_a = 0; i_a < 16; i_a = i_a + 1)
                for (i_b = 0; i_b < 16; i_b = i_b + 1)
                    for (i_c = 0; i_c < 2; i_c = i_c + 1) begin
                        op_select = i_op; a = i_a; b = i_b; cin = i_c;
                        #1;
                        exp5 = a + b + cin;
                        case (op_select)
                            2'b00: exp4 = a & b;
                            2'b01: exp4 = a | b;
                            2'b10: exp4 = a ^ b;
                            2'b11: exp4 = exp5[3:0];
                        endcase
                        // Cout is the FA carry in every mode
                        if (result !== exp4 || cout !== exp5[4]) begin
                            sweep_fail = sweep_fail + 1;
                            if (sweep_fail <= 10)
                                $display("[FAIL] sweep: OpSel=%b A=%h B=%h Cin=%b => R=%h Cout=%b (exp %h, %b)",
                                         op_select, a, b, cin, result, cout, exp4, exp5[4]);
                        end
                    end
        test_num = test_num + 1;
        if (sweep_fail == 0) begin
            pass_count = pass_count + 1;
            $display("[PASS] Test %0d (SWEEP): all 2048 combinations match", test_num);
        end else begin
            fail_count = fail_count + 1;
            $display("[FAIL] Test %0d (SWEEP): %0d mismatches", test_num, sweep_fail);
        end

        // ===================== Summary =====================
        $display("\n==============================================");
        $display("  Results: %0d PASSED, %0d FAILED out of %0d tests",
                 pass_count, fail_count, test_num);
        $display("==============================================");

        if (fail_count == 0)
            $display("  >>> ALL TESTS PASSED <<<");
        else
            $display("  >>> SOME TESTS FAILED <<<");

        $finish;
    end

    initial begin
        $dumpfile("alu_4bit.vcd");
        $dumpvars(0, tb_alu_4bit);
    end

endmodule
