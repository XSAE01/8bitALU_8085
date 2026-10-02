//=============================================================================
// Testbench: tb_alu_8bit
// Description: Comprehensive testbench for the 8-bit ALU (combinational).
//              Tests all 16 ALU operations with known expected results.
//              Verifies arithmetic, logic, rotate, and flag behavior.
//=============================================================================

`timescale 1ns / 1ps

module tb_alu_8bit;

    // Inputs
    reg  [7:0] a, b;
    reg  [3:0] alu_op;
    reg        carry_flag;

    // Outputs
    wire [7:0] result;
    wire       flag_s, flag_z, flag_ac, flag_p, flag_cy;

    // Instantiate UUT
    alu_8bit uut (
        .a          (a),
        .b          (b),
        .alu_op     (alu_op),
        .carry_flag (carry_flag),
        .result     (result),
        .flag_s     (flag_s),
        .flag_z     (flag_z),
        .flag_ac    (flag_ac),
        .flag_p     (flag_p),
        .flag_cy    (flag_cy)
    );

    // Test tracking
    integer pass_count = 0;
    integer fail_count = 0;
    integer test_num   = 0;

    // Task: check result and flags
    task check;
        input [7:0]  exp_result;
        input        exp_cy;
        input [127:0] desc;
        begin
            test_num = test_num + 1;
            if (result === exp_result && flag_cy === exp_cy) begin
                pass_count = pass_count + 1;
                $display("[PASS] %0d. %-20s | A=%h B=%h CY_in=%b | Result=%h | S=%b Z=%b AC=%b P=%b CY=%b",
                         test_num, desc, a, b, carry_flag, result,
                         flag_s, flag_z, flag_ac, flag_p, flag_cy);
            end else begin
                fail_count = fail_count + 1;
                $display("[FAIL] %0d. %-20s | A=%h B=%h CY_in=%b | Result=%h (exp %h) | CY=%b (exp %b)",
                         test_num, desc, a, b, carry_flag, result, exp_result,
                         flag_cy, exp_cy);
            end
        end
    endtask

    // Task: check with all flags
    task check_full;
        input [7:0]  exp_result;
        input        exp_s, exp_z, exp_ac, exp_p, exp_cy;
        input [127:0] desc;
        begin
            test_num = test_num + 1;
            if (result === exp_result && flag_s === exp_s && flag_z === exp_z &&
                flag_ac === exp_ac && flag_p === exp_p && flag_cy === exp_cy) begin
                pass_count = pass_count + 1;
                $display("[PASS] %0d. %-20s | A=%h B=%h | Result=%h | S=%b Z=%b AC=%b P=%b CY=%b",
                         test_num, desc, a, b, result,
                         flag_s, flag_z, flag_ac, flag_p, flag_cy);
            end else begin
                fail_count = fail_count + 1;
                $display("[FAIL] %0d. %-20s | A=%h B=%h | Got: R=%h S=%b Z=%b AC=%b P=%b CY=%b",
                         test_num, desc, a, b, result,
                         flag_s, flag_z, flag_ac, flag_p, flag_cy);
                $display("       Expected: R=%h S=%b Z=%b AC=%b P=%b CY=%b",
                         exp_result, exp_s, exp_z, exp_ac, exp_p, exp_cy);
            end
        end
    endtask

    initial begin
        $display("================================================================");
        $display("  8-bit ALU Testbench — Intel 8085 Operations");
        $display("================================================================\n");

        carry_flag = 0;

        // ===================================================================
        // ARITHMETIC OPERATIONS
        // ===================================================================
        $display("--- ADD (0000) ---");

        // ADD: 30h + 12h = 42h
        a = 8'h30; b = 8'h12; alu_op = 4'b0000; carry_flag = 0; #10;
        check(8'h42, 1'b0, "ADD 30+12=42       ");

        // ADD: FFh + 01h = 00h (carry)
        a = 8'hFF; b = 8'h01; alu_op = 4'b0000; carry_flag = 0; #10;
        check(8'h00, 1'b1, "ADD FF+01=00 CY    ");

        // ADD: Result = 0 → Zero flag
        a = 8'h00; b = 8'h00; alu_op = 4'b0000; carry_flag = 0; #10;
        check_full(8'h00, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, "ADD 00+00 Zero     ");

        // ADD: Negative result (MSB=1) → Sign flag
        a = 8'h7F; b = 8'h01; alu_op = 4'b0000; carry_flag = 0; #10;
        check_full(8'h80, 1'b1, 1'b0, 1'b1, 1'b0, 1'b0, "ADD 7F+01 Sign     ");

        // ADD: AC test: 0Fh + 01h = 10h, carry from bit3→bit4
        a = 8'h0F; b = 8'h01; alu_op = 4'b0000; carry_flag = 0; #10;
        check_full(8'h10, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, "ADD 0F+01 AC       ");

        $display("\n--- ADC (0001) ---");

        // ADC: 30h + 12h + 1 = 43h
        a = 8'h30; b = 8'h12; alu_op = 4'b0001; carry_flag = 1; #10;
        check(8'h43, 1'b0, "ADC 30+12+1=43     ");

        // ADC: FFh + 00h + 1 = 00h (carry)
        a = 8'hFF; b = 8'h00; alu_op = 4'b0001; carry_flag = 1; #10;
        check(8'h00, 1'b1, "ADC FF+00+1 CY     ");

        $display("\n--- SUB (0010) ---");

        // SUB: 42h - 12h = 30h
        a = 8'h42; b = 8'h12; alu_op = 4'b0010; carry_flag = 0; #10;
        check(8'h30, 1'b0, "SUB 42-12=30       ");

        // SUB: 10h - 10h = 00h (zero)
        a = 8'h10; b = 8'h10; alu_op = 4'b0010; carry_flag = 0; #10;
        check(8'h00, 1'b0, "SUB 10-10=00 Zero  ");

        // SUB: 05h - 10h = F5h (borrow/carry set)
        a = 8'h05; b = 8'h10; alu_op = 4'b0010; carry_flag = 0; #10;
        check(8'hF5, 1'b1, "SUB 05-10=F5 CY    ");

        $display("\n--- SBB (0011) ---");

        // SBB: 42h - 12h - 1 = 2Fh
        a = 8'h42; b = 8'h12; alu_op = 4'b0011; carry_flag = 1; #10;
        check(8'h2F, 1'b0, "SBB 42-12-1=2F     ");

        // SBB: 00h - 00h - 1 = FFh (borrow)
        a = 8'h00; b = 8'h00; alu_op = 4'b0011; carry_flag = 1; #10;
        check(8'hFF, 1'b1, "SBB 00-00-1=FF CY  ");

        $display("\n--- CMP (0111) ---");

        // CMP: A=42, B=42 → Result same as SUB but...
        a = 8'h42; b = 8'h42; alu_op = 4'b0111; carry_flag = 0; #10;
        check(8'h00, 1'b0, "CMP 42==42 Z=1     ");

        // CMP: A=42, B=50 → A < B, CY=1
        a = 8'h42; b = 8'h50; alu_op = 4'b0111; carry_flag = 0; #10;
        check(8'hF2, 1'b1, "CMP 42<50 CY=1     ");

        $display("\n--- INR (1111) ---");

        // INR: 41h + 1 = 42h (CY unchanged)
        a = 8'h41; b = 8'h00; alu_op = 4'b1111; carry_flag = 1; #10;
        check(8'h42, 1'b1, "INR 41+1=42 CY unch");

        // ===================================================================
        // LOGICAL OPERATIONS
        // ===================================================================
        $display("\n--- ANA (0100) ---");

        // ANA: A5h & 0Fh = 05h
        a = 8'hA5; b = 8'h0F; alu_op = 4'b0100; carry_flag = 0; #10;
        check_full(8'h05, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, "ANA A5&0F=05       ");

        $display("\n--- ORA (0110) ---");

        // ORA: A0h | 05h = A5h
        a = 8'hA0; b = 8'h05; alu_op = 4'b0110; carry_flag = 1; #10;
        check_full(8'hA5, 1'b1, 1'b0, 1'b0, 1'b1, 1'b0, "ORA A0|05=A5 CY=0  ");

        $display("\n--- XRA (0101) ---");

        // XRA: FFh ^ FFh = 00h
        a = 8'hFF; b = 8'hFF; alu_op = 4'b0101; carry_flag = 1; #10;
        check_full(8'h00, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, "XRA FF^FF=00 Z=1   ");

        // XRA: A5h ^ 5Ah = FFh
        a = 8'hA5; b = 8'h5A; alu_op = 4'b0101; carry_flag = 0; #10;
        check_full(8'hFF, 1'b1, 1'b0, 1'b0, 1'b1, 1'b0, "XRA A5^5A=FF       ");

        // ===================================================================
        // ROTATE OPERATIONS
        // ===================================================================
        $display("\n--- RLC (1000) ---");

        // RLC: A=81h (10000001) → 03h, CY=1
        a = 8'h81; b = 8'h00; alu_op = 4'b1000; carry_flag = 0; #10;
        check(8'h03, 1'b1, "RLC 81 -> 03 CY=1  ");

        $display("\n--- RRC (1001) ---");

        // RRC: A=81h (10000001) → C0h, CY=1
        a = 8'h81; b = 8'h00; alu_op = 4'b1001; carry_flag = 0; #10;
        check(8'hC0, 1'b1, "RRC 81 -> C0 CY=1  ");

        $display("\n--- RAL (1010) ---");

        // RAL: A=81h, CY=0 → 02h, CY=1
        a = 8'h81; b = 8'h00; alu_op = 4'b1010; carry_flag = 0; #10;
        check(8'h02, 1'b1, "RAL 81 CY=0->02    ");

        // RAL: A=81h, CY=1 → 03h, CY=1
        a = 8'h81; b = 8'h00; alu_op = 4'b1010; carry_flag = 1; #10;
        check(8'h03, 1'b1, "RAL 81 CY=1->03    ");

        $display("\n--- RAR (1011) ---");

        // RAR: A=81h, CY=0 → 40h, CY=1
        a = 8'h81; b = 8'h00; alu_op = 4'b1011; carry_flag = 0; #10;
        check(8'h40, 1'b1, "RAR 81 CY=0->40    ");

        // RAR: A=81h, CY=1 → C0h, CY=1
        a = 8'h81; b = 8'h00; alu_op = 4'b1011; carry_flag = 1; #10;
        check(8'hC0, 1'b1, "RAR 81 CY=1->C0    ");

        // ===================================================================
        // SPECIAL OPERATIONS
        // ===================================================================
        $display("\n--- CMA (1100) ---");

        // CMA: ~A5h = 5Ah
        a = 8'hA5; b = 8'h00; alu_op = 4'b1100; carry_flag = 0; #10;
        check(8'h5A, 1'b0, "CMA ~A5=5A         ");

        $display("\n--- STC (1101) ---");

        // STC: Set carry
        a = 8'h42; b = 8'h00; alu_op = 4'b1101; carry_flag = 0; #10;
        check(8'h42, 1'b1, "STC CY=1           ");

        $display("\n--- CMC (1110) ---");

        // CMC: Complement carry (0→1)
        a = 8'h42; b = 8'h00; alu_op = 4'b1110; carry_flag = 0; #10;
        check(8'h42, 1'b1, "CMC 0->1           ");

        // CMC: Complement carry (1→0)
        a = 8'h42; b = 8'h00; alu_op = 4'b1110; carry_flag = 1; #10;
        check(8'h42, 1'b0, "CMC 1->0           ");

        // ===================================================================
        // Summary
        // ===================================================================
        $display("\n================================================================");
        $display("  Results: %0d PASSED, %0d FAILED out of %0d tests",
                 pass_count, fail_count, test_num);
        $display("================================================================");

        if (fail_count == 0)
            $display("  >>> ALL TESTS PASSED <<<");
        else
            $display("  >>> SOME TESTS FAILED <<<");

        $finish;
    end

    initial begin
        $dumpfile("alu_8bit.vcd");
        $dumpvars(0, tb_alu_8bit);
    end

endmodule
