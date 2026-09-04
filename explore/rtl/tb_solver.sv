// Standalone cycle-counting testbench for alwaysud_solver.
//
// The K5 flow can only simulate three boards and takes ~40 s each. This drives the
// solver module directly, so a cycle model can be validated against the RTL on
// hundreds of held-out puzzles instead of three - which is what makes a hard1
// prediction trustworthy.
//
//   xrun -sv +define+SUD_MODE=1 sud_geom_pkg.sv alwaysud_solver.sv tb_solver.sv \
//        +PUZZLES=<file> +OUT=<file>
//
// Input : one puzzle per line, 81 chars of 1-9 with . or 0 for empty.
// Output: "<line> <cycles> <ok|FAIL> <81-digit grid>"
`timescale 1ns/1ps
module tb_solver;

    logic clk = 0, rst_n = 0, start = 0;
    logic [8:0][8:0][3:0] puzzle_in;
    logic [80:0][3:0]     pz_flat;
    logic done, success;
    logic [8:0][8:0][3:0] solved;
    logic [80:0][3:0]     sol_flat;

    assign puzzle_in = pz_flat;
    assign sol_flat  = solved;

    always #5 clk = ~clk;

    alwaysud_solver dut (.clk, .rst_n, .puzzle_in, .start, .done, .success,
                         .solved_puzzle(solved));

    string pfile, ofile, line;
    int fin, fout, n, code;
    longint unsigned cyc;
    int MAXCYC = 200000000;

    initial begin
        if (!$value$plusargs("PUZZLES=%s", pfile)) begin
            $display("need +PUZZLES=<file>"); $finish;
        end
        if (!$value$plusargs("OUT=%s", ofile)) ofile = "tb_out.txt";
        fin  = $fopen(pfile, "r");
        fout = $fopen(ofile, "w");
        if (fin == 0) begin $display("cannot open %s", pfile); $finish; end

        n = 0;
        repeat (4) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        while ($fgets(line, fin) > 0) begin
            int k; byte ch;
            if (line.len() < 81) continue;
            k = 0;
            for (int i = 0; i < line.len() && k < 81; i++) begin
                ch = line[i];
                if (ch == "." || ch == "0") begin pz_flat[k] = 4'd0; k++; end
                else if (ch >= "1" && ch <= "9") begin pz_flat[k] = 4'(ch - "0"); k++; end
            end
            if (k != 81) continue;
            n++;

            // full reset between puzzles: the solver holds done until reset
            rst_n = 0; @(posedge clk); @(posedge clk); rst_n = 1; @(posedge clk);

            start = 1; @(posedge clk); start = 0;
            cyc = 0;
            while (!done && cyc < MAXCYC) begin @(posedge clk); cyc++; end

            begin
                string g; int bad;
                g = ""; bad = 0;
                for (int c = 0; c < 81; c++) g = {g, string'("0" + sol_flat[c])};
                if (!done) bad = 2;
                else if (!success) bad = 1;
                $fdisplay(fout, "%0d %0d %s %s", n, cyc, bad == 0 ? "ok" :
                          (bad == 1 ? "NOSOL" : "TIMEOUT"), g);
            end
            if (n % 200 == 0) $display("  ... %0d puzzles", n);
        end
        $display("tb_solver: %0d puzzles -> %s", n, ofile);
        $fclose(fin); $fclose(fout);
        $finish;
    end
endmodule
