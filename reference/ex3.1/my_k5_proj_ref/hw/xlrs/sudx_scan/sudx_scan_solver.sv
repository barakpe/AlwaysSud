module sudx_scan_solver (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [8:0][8:0][3:0] puzzle_in,
    input logic         start,
    output logic        done,
    output logic        success,   
    output logic [8:0][8:0][3:0] solved_puzzle
);

    // Internal grid array
    logic [3:0] grid [0:8][0:8];

    // Traversal pointers
    logic [3:0] row, col;
    logic [3:0] val;

    // Backtrack stack storing packed entries: {row[3:0], col[3:0], val[3:0]} = 12 bits
    logic [11:0] stack [0:80];
    logic [6:0]  sp;

    // FSM State Encoding
    typedef enum logic [2:0] {
        IDLE,
        INIT,
        START,
        FIND_EMPTY,
        TRY_VAL,
        BACKTRACK,
        DONE_SUCCESS,
        DONE_FAIL
    } state_t;

    state_t state;

    // Synthesizable lookup for 3x3 box starting indices (avoids hardware division)
    function automatic logic [3:0] get_box_start(input logic [3:0] idx);
        if (idx < 4'd3)      return 4'd0;
        else if (idx < 4'd6) return 4'd3;
        else                 return 4'd6;
    endfunction

    // Pure combinational constraint checker
    function automatic logic is_valid(
        input logic [3:0] r,
        input logic [3:0] c,
        input logic [3:0] v
    );
        logic valid;
        logic [3:0] br, bc;
        
        valid = 1'b1;
        br = get_box_start(r);
        bc = get_box_start(c);

        // Check Row and Column conflict
        for (int i = 0; i < 9; i++) begin
            if (grid[r][i] == v) valid = 1'b0;
            if (grid[i][c] == v) valid = 1'b0;
        end

        // Check 3x3 Sub-grid conflict
        for (int dr = 0; dr < 3; dr++) begin
            for (int dc = 0; dc < 3; dc++) begin
                if (grid[br + dr][bc + dc] == v) valid = 1'b0;
            end
        end

        return valid;
    endfunction

    // Main Control FSM
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state   <= IDLE;
            sp      <= 7'd0;
            row     <= 4'd0;
            col     <= 4'd0;
            val     <= 4'd1;
            success <= 1'b0;
            done    <= 1'b0;

            for (int r = 0; r < 9; r++) begin
                 for (int c = 0; c < 9; c++) begin
                     grid[r][c] <= 0;
                 end
            end

        end else begin
            case (state)
 
                IDLE: if (start) state <= INIT ;

                INIT: begin
                    done    <= 1'b0;
                    success <= 1'b0;
                    sp      <= 7'd0;
                    row     <= 4'd0;
                    col     <= 4'd0;
                    val     <= 4'd1;

                    // Capture input matrix into registers
                    for (int r = 0; r < 9; r++) begin
                        for (int c = 0; c < 9; c++) begin
                            grid[r][c] <= puzzle_in[r][c];
                        end
                    end
                    state <= FIND_EMPTY;
                end

                FIND_EMPTY: begin
                    if (grid[row][col] == 4'd0) begin
                        val   <= 4'd1;
                        state <= TRY_VAL;
                    end else begin
                        if (col == 4'd8) begin
                            if (row == 4'd8) begin
                                state <= DONE_SUCCESS; // All cells filled
                            end else begin
                                col <= 4'd0;
                                row <= row + 1'b1;
                            end
                        end else begin
                            col <= col + 1'b1;
                        end
                    end
                end

                TRY_VAL: begin
                    if (val > 4'd9) begin

                        // No valid value found for this cell: reset it to
                        // empty before unwinding, otherwise FIND_EMPTY will
                        // treat the stale leftover value as a filled cell
                        // and skip it on the way back down the search tree.
                        grid[row][col] <= 4'd0;


                        state <= BACKTRACK;
                    end else if (is_valid(row, col, val)) begin
                        grid[row][col] <= val;
                        
                        // Push cell state {row, col, val} to stack
                        stack[sp] <= {row, col, val};
                        sp        <= sp + 1'b1;

                        val   <= 4'd1;
                        state <= FIND_EMPTY;
                    end else begin
                        val <= val + 1'b1;
                    end
                end

                BACKTRACK: begin
                    if (sp == 7'd0) begin
                        state <= DONE_FAIL; // No possible valid state left
                    end else begin
                        // Pop previous state from stack
                        row <= stack[sp-1][11:8];
                        col <= stack[sp-1][7:4];
                        val <= stack[sp-1][3:0] + 1'b1;
                        sp  <= sp - 1'b1;

                        state <= TRY_VAL;
                    end
                end

                DONE_SUCCESS: begin
                    success <= 1'b1;
                    done    <= 1'b1;
                end

                DONE_FAIL: begin
                    success <= 1'b0;
                    done    <= 1'b1;
                end

                default: state <= IDLE;

            endcase
        end
    end

    // Drive solved grid to output
    always_comb begin
        for (int r = 0; r < 9; r++) begin
            for (int c = 0; c < 9; c++) begin
                solved_puzzle[r][c] = grid[r][c];
            end
        end
    end

endmodule