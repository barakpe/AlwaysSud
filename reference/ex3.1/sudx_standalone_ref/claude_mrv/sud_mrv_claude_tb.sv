`timescale 1ns/1ps
module tb_user;
    logic clk = 0;
    logic rst_n;
    logic start;
    logic [8:0][8:0][3:0] puzzle_in;
    logic busy, done, success;
    logic [8:0][8:0][3:0] puzzle_solved;

    sud_solver_mrv_claude dut (.clk(clk), .rst_n(rst_n), .start(start), .puzzle_in(puzzle_in),
                        .busy(busy), .done(done), .success(success), .puzzle_solved(puzzle_solved));

    always #5 clk = ~clk;
    integer cycle_count;
    always @(posedge clk) if (busy) cycle_count = cycle_count + 1;

    task automatic load_user;
        begin
            puzzle_in = { 

               /*
               // 51 blanks         
               {4'd5 , 4'd3 , 4'd0 , 4'd0 , 4'd7 , 4'd0 , 4'd0 , 4'd0 , 4'd0},
               {4'd6 , 4'd0 , 4'd0 , 4'd1 , 4'd9 , 4'd5 , 4'd0 , 4'd0 , 4'd0},
               {4'd0 , 4'd9 , 4'd8 , 4'd0 , 4'd0 , 4'd0 , 4'd0 , 4'd6 , 4'd0},
               {4'd8 , 4'd0 , 4'd0 , 4'd0 , 4'd6 , 4'd0 , 4'd0 , 4'd0 , 4'd3},
               {4'd4 , 4'd0 , 4'd0 , 4'd8 , 4'd0 , 4'd3 , 4'd0 , 4'd0 , 4'd1},
               {4'd7 , 4'd0 , 4'd0 , 4'd0 , 4'd2 , 4'd0 , 4'd0 , 4'd0 , 4'd6},
               {4'd0 , 4'd6 , 4'd0 , 4'd0 , 4'd0 , 4'd0 , 4'd2 , 4'd8 , 4'd0},
               {4'd0 , 4'd0 , 4'd0 , 4'd4 , 4'd1 , 4'd9 , 4'd0 , 4'd0 , 4'd5},
               {4'd0 , 4'd0 , 4'd0 , 4'd0 , 4'd8 , 4'd0 , 4'd0 , 4'd7 , 4'd9} 
               */

               // hard1
               {4'd4, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd8, 4'd0, 4'd5},
               {4'd0, 4'd3, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0},
               {4'd0, 4'd0, 4'd0, 4'd7, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0}, 
               {4'd0, 4'd2, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd6, 4'd0},
               {4'd0, 4'd0, 4'd0, 4'd0, 4'd8, 4'd0, 4'd4, 4'd0, 4'd0},
               {4'd0, 4'd0, 4'd0, 4'd0, 4'd1, 4'd0, 4'd0, 4'd0, 4'd0}, 
               {4'd0, 4'd0, 4'd0, 4'd6, 4'd0, 4'd3, 4'd0, 4'd7, 4'd0},
               {4'd5, 4'd0, 4'd0, 4'd2, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0},
               {4'd1, 4'd0, 4'd4, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0, 4'd0}  
 
            };


        end
    endtask

    logic [3:0] solved_copy [0:8][0:8];
    genvar gr, gc;
    generate
        for (gr=0; gr<9; gr=gr+1) begin : GR
            for (gc=0; gc<9; gc=gc+1) begin : GC
                assign solved_copy[gr][gc] = puzzle_solved[gr][gc];
            end
        end
    endgenerate

    integer r,c;
    initial begin
        cycle_count = 0;
        rst_n = 0; start = 0;
        load_user();
        repeat (3) @(posedge clk);
        rst_n = 1;
        @(posedge clk);
        start = 1;
        @(posedge clk);
        start = 0;
        wait (done == 1);
        @(posedge clk);
        $display("success=%0d  cycles(busy)=%0d", success, cycle_count);
        if (success) begin
            for (r=0;r<9;r++) begin
                $write("  ");
                for (c=0;c<9;c++) $write("%0d ", solved_copy[r][c]);
                $write("\n");
            end
        end
        $finish;
    end
endmodule
