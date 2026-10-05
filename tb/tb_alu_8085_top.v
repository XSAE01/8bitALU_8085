//=============================================================================
// Testbench: tb_alu_8085_top
// Description: Top-level integration testbench for the complete 8085 ALU
//              subsystem (ALU + FSM Controller + Registers).
//              Tests the full pipeline: Load A → Load B → Load Op → Execute → Done
//              Every operation is checked by a scoreboard against the shared
//              reference model (alu_ref_model.vh), then an exhaustive sweep
//              runs every {op, A, B} through the pipeline. DAA is checked
//              against decimal arithmetic for every BCD pair, and DAD
//              against 16-bit addition.
//              Compile with -I <tb dir> so the `include resolves.
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
    reg  [4:0] alu_op_in;

    // Outputs
    wire [7:0] acc_out;
    wire [4:0] flags_out;
    wire [7:0] flag_reg_out;
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
        .flags_out  (flags_out),
        .flag_reg_out (flag_reg_out),
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
    // Scoreboard: accumulator + flag assertions
    // =========================================================================
    // After every operation, the architectural state is checked against the
    // shared reference model (alu_ref_model.vh):
    //   Acc   = ref_result(A, B, op, flags_before) (CMP: Acc = A, not written)
    //   Flags = ref_flags (A, B, op, flags_before)
    //   flag_reg_out = 8085 PSW layout {S, Z, 0, AC, 0, P, 0, CY}
    //   done pulsed exactly once, FSM back in S0
    // flags_before is the model's copy of the flag register, so this also
    // checks that the register feeds the flags back into the ALU correctly.
    `include "alu_ref_model.vh"

    integer acc_fail_count   = 0;
    integer flag_fail_count  = 0;
    integer proto_fail_count = 0;   // done / state / PSW layout
    integer op_count         = 0;

    reg  [4:0] model_flags;         // Expected flag register contents
    reg  [7:0] exp_acc;
    reg  [4:0] exp_flags;

    integer done_count = 0;
    always @(posedge clk)
        if (done) done_count = done_count + 1;

    task check_model;
        input [7:0] op_a, op_b;
        input [4:0] op_code;
        input integer done_seen;
        begin
            op_count  = op_count + 1;
            exp_acc   = (op_code == 5'b00111) ? op_a
                                              : ref_result(op_a, op_b, op_code, model_flags);
            exp_flags = ref_flags(op_a, op_b, op_code, model_flags);

            if (acc_out !== exp_acc) begin
                acc_fail_count = acc_fail_count + 1;
                $display("[ASSERT] t=%0t op=%b A=%h B=%h flags_before=%b | Acc got %h exp %h",
                         $time, op_code, op_a, op_b, model_flags, acc_out, exp_acc);
            end
            if (flags_out !== exp_flags) begin
                flag_fail_count = flag_fail_count + 1;
                $display("[ASSERT] t=%0t op=%b A=%h B=%h flags_before=%b | SZAPC got %b exp %b",
                         $time, op_code, op_a, op_b, model_flags, flags_out, exp_flags);
            end
            if (flag_reg_out !== {flags_out[4:3], 1'b0, flags_out[2], 1'b0,
                                  flags_out[1], 1'b0, flags_out[0]}) begin
                proto_fail_count = proto_fail_count + 1;
                $display("[ASSERT] t=%0t PSW layout: flag_reg_out=%b flags_out=%b",
                         $time, flag_reg_out, flags_out);
            end
            if (done_seen !== 1 || state_out !== 3'd0) begin
                proto_fail_count = proto_fail_count + 1;
                $display("[ASSERT] t=%0t op=%b | done pulses=%0d (exp 1), state=%0d (exp 0)",
                         $time, op_code, done_seen, state_out);
            end

            // Resync to the DUT so one bad op doesn't cascade into every
            // later check (it has already been counted above)
            model_flags = flags_out;
        end
    endtask

    // =========================================================================
    // Task: run one complete ALU operation through the FSM pipeline and
    // check it against the model.
    // Pipeline: S0(idle) → S1(load_a) → S2(load_b) → S3(load_op)
    //           → S4(execute) → S5(done) → S0(idle)
    // =========================================================================
    integer done_before;

    // Sweep variables
    integer i_op, i_a, i_b;
    integer sweep_start_ops, sweep_start_fails;

    // BCD (ADD + DAA) and 16-bit DAD semantic checks
    integer i_x, i_y, i_d;
    integer bcd_fail_count = 0;
    integer dad_fail_count = 0;
    reg  [7:0]  bcd_x, bcd_y, bcd_sum;
    reg         bcd_cy;
    reg  [15:0] hl, rp;
    reg  [16:0] dad_sum;
    reg  [7:0]  dad_lo;
    reg  [3:0]  szap_before;

    function [7:0] to_bcd;              // 0..99 → packed BCD
        input integer n;
        to_bcd = ((n / 10) << 4) | (n % 10);
    endfunction

    // DAD HL, rp: DADL on the low bytes, then DADH on the high bytes
    task run_dad;
        input [15:0] hl_in, rp_in;
        begin
            szap_before = flags_out[4:1];
            run_op(hl_in[7:0],  rp_in[7:0],  5'b10010);    // DADL
            dad_lo = acc_out;
            run_op(hl_in[15:8], rp_in[15:8], 5'b10011);    // DADH
            dad_sum = hl_in + rp_in;
            if ({flag_cy, acc_out, dad_lo} !== dad_sum ||
                flags_out[4:1] !== szap_before) begin
                dad_fail_count = dad_fail_count + 1;
                $display("[ASSERT] DAD %h + %h: got CY=%b HL=%h%h SZAP=%b, exp CY=%b HL=%h SZAP=%b",
                         hl_in, rp_in, flag_cy, acc_out, dad_lo, flags_out[4:1],
                         dad_sum[16], dad_sum[15:0], szap_before);
            end
        end
    endtask

    task run_op;
        input [7:0]  op_a;
        input [7:0]  op_b;
        input [4:0]  op_code;
        begin
            // Setup inputs
            data_in_a = op_a;
            data_in_b = op_b;
            alu_op_in = op_code;
            done_before = done_count;

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
            #1;     // Let the done counter for this edge settle

            check_model(op_a, op_b, op_code, done_count - done_before);
        end
    endtask

    // Task: run_op plus a log line, for the directed tests
    task execute_op;
        input [7:0]  op_a;
        input [7:0]  op_b;
        input [4:0]  op_code;
        input [127:0] desc;
        begin
            run_op(op_a, op_b, op_code);

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
        alu_op_in = 5'h00;

        // Reset for 3 clock cycles
        repeat (3) @(posedge clk);
        rst = 1'b0;
        @(posedge clk);

        // Reset state: Acc = 00h, flags = {S=0, Z=1, AC=0, P=1, CY=0}
        model_flags = 5'b01010;
        if (acc_out !== 8'h00 || flags_out !== model_flags || state_out !== 3'd0) begin
            proto_fail_count = proto_fail_count + 1;
            $display("[ASSERT] Reset state: Acc=%h flags=%b state=%0d (exp 00 / 01010 / 0)",
                     acc_out, flags_out, state_out);
        end

        $display("--- Reset complete. Starting operations ---\n");

        // =============================================================
        // Test 1: ADD — 30h + 12h = 42h
        // =============================================================
        $display("Test 1: ADD");
        execute_op(8'h30, 8'h12, 4'b0000, "ADD 30+12          ");
        check_acc(8'h42, "ADD result         ");

        // =============================================================
        // Test 2: SUB — 42h - 12h = 30h (each op reloads A from data_in_a)
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
        // The FSM skips the write-back for CMP, so A keeps the loaded 42h
        // (the scoreboard also checks Z = 1, CY = 0)
        check_acc(8'h42, "CMP acc unchanged  ");

        // =============================================================
        // Test 12: SBB — 42h - 12h - CY, with CY = 0 left by the CMP
        // =============================================================
        $display("\nTest 12: SBB");
        execute_op(8'h42, 8'h12, 4'b0011, "SBB 42-12-CY       ");
        check_acc(8'h30, "SBB result         ");

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
        // Test 17-18: DCR and DAD through the pipeline
        // =============================================================
        $display("\nTest 17: DCR");
        execute_op(8'h01, 8'h00, 5'b10000, "DCR 01->00         ");
        check_acc(8'h00, "DCR result         ");

        $display("\nTest 18: DAD 12F0h + 0F20h = 2210h");
        run_dad(16'h12F0, 16'h0F20);
        check_acc(8'h22, "DAD high byte      ");

        // =============================================================
        // BCD check: every two-digit BCD pair, ADD then DAA
        // =============================================================
        // 100 × 100 = 10,000 pairs. Acc must be the BCD sum mod 100 and
        // CY must be the decimal carry. The scoreboard checks every op too.
        $display("\n--- BCD sweep (ADD + DAA) ---");
        $dumpoff;
        for (i_x = 0; i_x < 100; i_x = i_x + 1)
            for (i_y = 0; i_y < 100; i_y = i_y + 1) begin
                bcd_x = to_bcd(i_x);
                bcd_y = to_bcd(i_y);
                run_op(bcd_x, bcd_y, 5'b00000);         // ADD
                run_op(acc_out, 8'h00, 5'b10001);       // DAA
                bcd_sum = to_bcd((i_x + i_y) % 100);
                bcd_cy  = (i_x + i_y) >= 100;
                if (acc_out !== bcd_sum || flag_cy !== bcd_cy) begin
                    bcd_fail_count = bcd_fail_count + 1;
                    $display("[ASSERT] BCD %h + %h: got CY=%b Acc=%h, exp CY=%b Acc=%h",
                             bcd_x, bcd_y, flag_cy, acc_out, bcd_cy, bcd_sum);
                end
            end
        $dumpon;
        $display("  10000 pairs, %0d failures", bcd_fail_count);

        // =============================================================
        // DAD check: corner cases + 20,000 pseudo-random 16-bit adds
        // =============================================================
        $display("\n--- DAD sweep (DADL + DADH) ---");
        $dumpoff;
        run_dad(16'hFFFF, 16'h0001);
        run_dad(16'h00FF, 16'h0001);
        run_dad(16'h8000, 16'h8000);
        run_dad(16'hFFFF, 16'hFFFF);
        run_dad(16'h0000, 16'h0000);
        hl = 16'h1234;                          // Fixed seed: reproducible
        rp = 16'hBEEF;
        for (i_d = 0; i_d < 20000; i_d = i_d + 1) begin
            hl = {hl[14:0], hl[15] ^ hl[13] ^ hl[12] ^ hl[10]};   // 16-bit LFSR
            rp = {rp[14:0], rp[15] ^ rp[13] ^ rp[12] ^ rp[10]};
            run_dad(hl, rp);
        end
        $dumpon;
        $display("  20005 additions, %0d failures", dad_fail_count);

        // =============================================================
        // Exhaustive sweep through the full pipeline
        // =============================================================
        // Every {op, A, B} (32 × 256 × 256 = 2,097,152 operations, including
        // the 12 reserved opcodes), checked
        // by the scoreboard. The flag register is never forced: each op
        // starts from whatever flags the previous op left, so CY_in and the
        // pass-through flags vary naturally and the feedback path is
        // exercised on every op. (Every {op, A, B, flags} combination is
        // already covered combinationally by tb_alu_8bit.)
        $display("\n--- Exhaustive pipeline sweep ---");
        sweep_start_ops   = op_count;
        sweep_start_fails = acc_fail_count + flag_fail_count + proto_fail_count;
        $dumpoff;                               // Keep the VCD small
        for (i_op = 0; i_op < 32; i_op = i_op + 1)
            for (i_a = 0; i_a < 256; i_a = i_a + 1)
                for (i_b = 0; i_b < 256; i_b = i_b + 1)
                    run_op(i_a, i_b, i_op);
        $dumpon;
        $display("  %0d operations, %0d assertion failures",
                 op_count - sweep_start_ops,
                 acc_fail_count + flag_fail_count + proto_fail_count - sweep_start_fails);

        // =============================================================
        // Summary
        // =============================================================
        $display("\n================================================================");
        $display("  Results: %0d PASSED, %0d FAILED out of %0d tests",
                 pass_count, fail_count, test_num);
        $display("  Operations checked:         %0d", op_count);
        $display("  Acc assertion failures:     %0d", acc_fail_count);
        $display("  Flag assertion failures:    %0d", flag_fail_count);
        $display("  Protocol assertion failures: %0d", proto_fail_count);
        $display("  BCD (DAA) failures:         %0d", bcd_fail_count);
        $display("  DAD failures:               %0d", dad_fail_count);
        $display("================================================================");

        if (fail_count == 0 && acc_fail_count == 0 &&
            flag_fail_count == 0 && proto_fail_count == 0 &&
            bcd_fail_count == 0 && dad_fail_count == 0)
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

    // Timeout safety: the sweep alone is ~2.1M ops × 7 cycles × 20 ns ≈ 294 ms
    initial begin
        #400_000_000;
        $display("[ERROR] Simulation timeout!");
        $finish;
    end

endmodule
