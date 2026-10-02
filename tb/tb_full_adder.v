//=============================================================================
// Testbench: tb_full_adder
// Description: Exhaustive test of the 1-bit Full Adder.
//              Tests all 8 input combinations of {A, B, Cin}.
//=============================================================================

`timescale 1ns / 1ps

module tb_full_adder;

    // Inputs
    reg  a, b, cin;

    // Outputs
    wire sum, cout;

    // Instantiate Unit Under Test
    full_adder uut (
        .a    (a),
        .b    (b),
        .cin  (cin),
        .sum  (sum),
        .cout (cout)
    );

    // Expected values
    reg expected_sum, expected_cout;

    // Test counter
    integer pass_count = 0;
    integer fail_count = 0;
    integer test_num   = 0;

    // Task: check result
    task check;
        input exp_sum, exp_cout;
        begin
            test_num = test_num + 1;
            if (sum === exp_sum && cout === exp_cout) begin
                pass_count = pass_count + 1;
                $display("[PASS] Test %0d: A=%b B=%b Cin=%b => Sum=%b Cout=%b",
                         test_num, a, b, cin, sum, cout);
            end else begin
                fail_count = fail_count + 1;
                $display("[FAIL] Test %0d: A=%b B=%b Cin=%b => Sum=%b Cout=%b (Expected Sum=%b Cout=%b)",
                         test_num, a, b, cin, sum, cout, exp_sum, exp_cout);
            end
        end
    endtask

    // Main test
    initial begin
        $display("==============================================");
        $display("  Full Adder Testbench");
        $display("==============================================");
        $display("");

        // Exhaustive test: all 8 combinations
        a = 0; b = 0; cin = 0; #10; check(0, 0);  // 0+0+0 = 0, C=0
        a = 0; b = 0; cin = 1; #10; check(1, 0);  // 0+0+1 = 1, C=0
        a = 0; b = 1; cin = 0; #10; check(1, 0);  // 0+1+0 = 1, C=0
        a = 0; b = 1; cin = 1; #10; check(0, 1);  // 0+1+1 = 2, C=1
        a = 1; b = 0; cin = 0; #10; check(1, 0);  // 1+0+0 = 1, C=0
        a = 1; b = 0; cin = 1; #10; check(0, 1);  // 1+0+1 = 2, C=1
        a = 1; b = 1; cin = 0; #10; check(0, 1);  // 1+1+0 = 2, C=1
        a = 1; b = 1; cin = 1; #10; check(1, 1);  // 1+1+1 = 3, C=1

        $display("");
        $display("==============================================");
        $display("  Results: %0d PASSED, %0d FAILED out of %0d tests",
                 pass_count, fail_count, test_num);
        $display("==============================================");

        if (fail_count == 0)
            $display("  >>> ALL TESTS PASSED <<<");
        else
            $display("  >>> SOME TESTS FAILED <<<");

        $finish;
    end

    // Optional: dump waveforms
    initial begin
        $dumpfile("full_adder.vcd");
        $dumpvars(0, tb_full_adder);
    end

endmodule
