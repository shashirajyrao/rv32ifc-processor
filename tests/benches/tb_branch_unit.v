// tb_branch_unit.v -- self-checking testbench for branch_unit.v (plain Verilog-2001)

`timescale 1ns/1ps

module tb_branch_unit;

    reg  [31:0] a, b;
    reg  [2:0]  funct3;
    wire        take;

    integer errors, checks;
    integer f, j, k, n;

    branch_unit dut (.a(a), .b(b), .funct3(funct3), .take(take));

    // Reference model; signed compare done via the sign bits, not $signed
    function model;
        input [31:0] fa;
        input [31:0] fb;
        input [2:0]  ff3;
        reg lt_u, lt_s;
        begin
            lt_u = (fa < fb);
            if (fa[31] != fb[31]) lt_s = fa[31];     // negative is smaller
            else                  lt_s = lt_u;
            case (ff3)
                3'b000:  model = (fa == fb);
                3'b001:  model = (fa != fb);
                3'b100:  model = lt_s;
                3'b101:  model = ~lt_s;
                3'b110:  model = lt_u;
                3'b111:  model = ~lt_u;
                default: model = 1'b0;
            endcase
        end
    endfunction

    task check;
        input [31:0] ta;
        input [31:0] tb_;
        input [2:0]  tf;
        reg          exp;
        begin
            a = ta; b = tb_; funct3 = tf;
            #1;
            exp = model(ta, tb_, tf);
            checks = checks + 1;
            if (take !== exp) begin
                errors = errors + 1;
                $display("FAIL funct3=%b a=%h b=%h : got %b expected %b", tf, ta, tb_, take, exp);
            end
        end
    endtask

    reg [31:0] corner [0:8];

    initial begin
        errors = 0; checks = 0;
        corner[0] = 32'h0000_0000;
        corner[1] = 32'h0000_0001;
        corner[2] = 32'hFFFF_FFFF;   // -1 signed, max unsigned
        corner[3] = 32'h7FFF_FFFF;   // max positive
        corner[4] = 32'h8000_0000;   // min negative
        corner[5] = 32'h8000_0001;
        corner[6] = 32'hFFFF_FFFE;
        corner[7] = 32'h0000_0002;
        corner[8] = 32'hDEAD_BEEF;

        for (f = 0; f < 8; f = f + 1)
            for (j = 0; j < 9; j = j + 1)
                for (k = 0; k < 9; k = k + 1)
                    check(corner[j], corner[k], f[2:0]);

        for (n = 0; n < 20000; n = n + 1)
            check($random, $random, $unsigned($random) % 8);

        // equal operands, random values
        for (n = 0; n < 2000; n = n + 1) begin
            a = $random;
            check(a, a, $unsigned($random) % 8);
        end

        $display("----------------------------------------");
        if (errors == 0) $display("PASS: %0d checks, 0 errors", checks);
        else             $display("FAIL: %0d errors in %0d checks", errors, checks);
        $display("----------------------------------------");
        if (errors != 0) $fatal(1, "branch comparator test failed");
        $finish;
    end

endmodule
