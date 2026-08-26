`timescale 1ns / 1ps

module tb_sudoku_solver;

    // Clock and Control Signals
    logic        clk;
    logic        rst_n;
    logic [8:0][8:0][3:0] puzzle_in;
    
    // Outputs from DUT
    logic        success;
    logic        done;
    logic [8:0][8:0][3:0] puzzle_solved;

    // DUT Instantiation
    sudoku_solver dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .puzzle_in    (puzzle_in),
        .success      (success),
        .done         (done),
        .puzzle_solved(puzzle_solved)
    );

    // 100 MHz Clock Generation
    always #5 clk = ~clk;

    // ------------------------------------------------------------------------
    // Helper Tasks
    // ------------------------------------------------------------------------

    // Task: Print grid in readable Sudoku board layout
    task print_grid(input logic [8:0][8:0][3:0] grid);
        $display("+-------+-------+-------+");
        for (int r = 0; r < 9; r++) begin
            $write("| ");
            for (int c = 0; c < 9; c++) begin
                if (grid[r][c] == 0)
                    $write(". ");
                else
                    $write("%0d ", grid[r][c]);

                if ((c + 1) % 3 == 0) $write("| ");
            end
            $display("");
            if ((r + 1) % 3 == 0) $display("+-------+-------+-------+");
        end
    endtask

    // Function: Verify output board validity
    function automatic logic verify_solution(input logic [8:0][8:0][3:0] grid);
        logic [9:1] row_mask, col_mask, box_mask;
        int val;

        // Check rows and columns
        for (int i = 0; i < 9; i++) begin
            row_mask = '0;
            col_mask = '0;
            for (int j = 0; j < 9; j++) begin
                // Check Row
                val = grid[i][j];
                if (val < 1 || val > 9 || row_mask[val]) return 1'b0;
                row_mask[val] = 1'b1;

                // Check Column
                val = grid[j][i];
                if (val < 1 || val > 9 || col_mask[val]) return 1'b0;
                col_mask[val] = 1'b1;
            end
        end

        // Check 3x3 Sub-grids
        for (int br = 0; br < 9; br += 3) begin
            for (int bc = 0; bc < 9; bc += 3) begin
                box_mask = '0;
                for (int r = 0; r < 3; r++) begin
                    for (int c = 0; c < 3; c++) begin
                        val = grid[br + r][bc + c];
                        if (val < 1 || val > 9 || box_mask[val]) return 1'b0;
                        box_mask[val] = 1'b1;
                    end
                end
            end
        end

        return 1'b1; // Solution passes all rules
    endfunction

    // ------------------------------------------------------------------------
    // Main Test Stimulus
    // ------------------------------------------------------------------------
    initial begin
        clk   = 0;
        rst_n = 0;
        puzzle_in = '0;

        $display("==================================================");
        $display("        STARTING SUDOKU SOLVER TESTBENCH          ");
        $display("==================================================");

        // Apply Reset
        #20;
        rst_n = 1;
        #10;

        // --------------------------------------------------------------------
        // TEST CASE 1: Standard Solvable Puzzle
        // --------------------------------------------------------------------
        $display("\n--- TEST 1: Standard Solvable Puzzle ---");
        
        // Define puzzle array (0 denotes empty cell)
        puzzle_in = '{

            /*
            // 20 blanks
            '{4'd5 , 4'd0 , 4'd4  , 4'd6 , 4'd0 , 4'd8  , 4'd9 , 4'd1 , 4'd2},
            '{4'd0 , 4'd7 , 4'd2  , 4'd1 , 4'd0 , 4'd5  , 4'd0 , 4'd4 , 4'd8},
            '{4'd1 , 4'd0 , 4'd8  , 4'd0 , 4'd4 , 4'd2  , 4'd5 , 4'd6 , 4'd0}, 
            '{4'd8 , 4'd5 , 4'd0  , 4'd7 , 4'd6 , 4'd1  , 4'd4 , 4'd0 , 4'd3},
            '{4'd4 , 4'd2 , 4'd6  , 4'd8 , 4'd5 , 4'd0  , 4'd7 , 4'd9 , 4'd0},
            '{4'd7 , 4'd1 , 4'd3  , 4'd0 , 4'd2 , 4'd4  , 4'd8 , 4'd0 , 4'd6}, 
            '{4'd9 , 4'd6 , 4'd0  , 4'd5 , 4'd3 , 4'd7  , 4'd0 , 4'd8 , 4'd4},
            '{4'd2 , 4'd0 , 4'd7  , 4'd4 , 4'd1 , 4'd0  , 4'd6 , 4'd3 , 4'd5},
            '{4'd3 , 4'd4 , 4'd5  , 4'd2 , 4'd0 , 4'd6  , 4'd1 , 4'd0 , 4'd9}            
            */

           // 51 blanks         
           '{4'd5 , 4'd3 , 4'd0 , 4'd0 , 4'd7 , 4'd0 , 4'd0 , 4'd0 , 4'd0},
           '{4'd6 , 4'd0 , 4'd0 , 4'd1 , 4'd9 , 4'd5 , 4'd0 , 4'd0 , 4'd0},
           '{4'd0 , 4'd9 , 4'd8 , 4'd0 , 4'd0 , 4'd0 , 4'd0 , 4'd6 , 4'd0},
           '{4'd8 , 4'd0 , 4'd0 , 4'd0 , 4'd6 , 4'd0 , 4'd0 , 4'd0 , 4'd3},
           '{4'd4 , 4'd0 , 4'd0 , 4'd8 , 4'd0 , 4'd3 , 4'd0 , 4'd0 , 4'd1},
           '{4'd7 , 4'd0 , 4'd0 , 4'd0 , 4'd2 , 4'd0 , 4'd0 , 4'd0 , 4'd6},
           '{4'd0 , 4'd6 , 4'd0 , 4'd0 , 4'd0 , 4'd0 , 4'd2 , 4'd8 , 4'd0},
           '{4'd0 , 4'd0 , 4'd0 , 4'd4 , 4'd1 , 4'd9 , 4'd0 , 4'd0 , 4'd5},
           '{4'd0 , 4'd0 , 4'd0 , 4'd0 , 4'd8 , 4'd0 , 4'd0 , 4'd7 , 4'd9} 


        };

        $display("Input Board:");
        print_grid(puzzle_in);

        // Pulse Reset to load new input
        rst_n = 0;
        #20;
        rst_n = 1;

        // Wait for DUT to complete computation
        wait(done == 1'b1);
        #10;

        if (success) begin
            $display("\nSolver finished in SUCCESS state!");
            $display("Solved Board:");
            print_grid(puzzle_solved);

            // Self-checking assertion/verification
            if (verify_solution(puzzle_solved)) begin
                $display("[PASS] TEST 1: Solution verified against Sudoku rules.");
            end else begin
                $error("[FAIL] TEST 1: Solver claimed success, but output board violates rules!");
            end
        end else begin
            $error("[FAIL] TEST 1: Solver failed on a solvable puzzle.");
        end
    $finish; 
    end // initial

endmodule