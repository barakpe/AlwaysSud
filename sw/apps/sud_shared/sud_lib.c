#include <k5_libs.h>
#include <sud_lib.h>

//-----------------------------------------------------------------------------------------------------------

static unsigned char loaded_board[SIZE][SIZE]; // the non completed loaded board memorized for final check

void load_sud_board(unsigned char board[SIZE][SIZE]) {
         
    #ifdef HLCM    
      char sud_in_file_path[200] ;          
      char *k5_path = getenv("MY_K5_PROJ");
      #ifndef _GP_VAL_   
      bm_sprintf(sud_in_file_path,"%s/%s",k5_path,"$MY_K5_PROJ/sw/apps/sud_shared/sudoku_input_20blanks.txt"); // Easy one
      #else    
      bm_sprintf(sud_in_file_path,"%s/sudoku_input_%s.txt",sud_shared_path,EXPAND_AND_STRINGIFY(_GP_VAL_));  
      #endif 
      
    #else 
    char sud_in_file_path[80] ;                 
      #ifndef _GP_VAL_   
      bm_sprintf(sud_in_file_path,"%s","$MY_K5_PROJ/sw/apps/sud_shared/sudoku_input_20blanks.txt"); // Easy one
      #else    
      bm_sprintf(sud_in_file_path,"$MY_K5_PROJ/sw/apps/sud_shared/sudoku_input_%s.txt",EXPAND_AND_STRINGIFY(_GP_VAL_));  
      #endif
      
    #endif
          
    FILE_REF file_ref ; // assigned by load_hex_file( ... OPEN*) 
    // TODO call some python to generate sudoku_input.txt randomly ...
    load_hex_file(sud_in_file_path, &file_ref, (char *)board, SIZE*SIZE, OPEN_LOAD_CLOSE); // Keep Open 

    // Memorize loaded board for post solve checking

    for (int i=0;i<(SIZE*SIZE);i++) ((uint8_t*)loaded_board)[i] = ((uint8_t*)board)[i] ;
}       

//-----------------------------------------------------------------------------------------------------------


char is_solved(unsigned char board[9][9]) {
    int i, j, n, r, c, br, bc;

    unsigned char seen[9];

    printf("Checking Sudoku rules compatibility\n"); 

    /* check each row */
    for (r = 0; r < 9; r++) {
        for (i = 0; i < 9; i++) seen[i] = 0;
        for (c = 0; c < 9; c++) {
            n = board[r][c];
            if (n < 1 || n > 9) return 0;
            if (seen[n - 1]) return 0;
            seen[n - 1] = 1;
        }
    }

    /* check each column */
    for (c = 0; c < 9; c++) {
        for (i = 0; i < 9; i++) seen[i] = 0;
        for (r = 0; r < 9; r++) {
            n = board[r][c];
            if (seen[n - 1]) return 0;
            seen[n - 1] = 1;
        }
    }

    /* check each 3x3 box */
    for (br = 0; br < 9; br += 3) {
        for (bc = 0; bc < 9; bc += 3) {
            for (i = 0; i < 9; i++) seen[i] = 0;
            for (i = 0; i < 3; i++) {
                for (j = 0; j < 3; j++) {
                    n = board[br + i][bc + j];
                    if (seen[n - 1]) return 0;
                    seen[n - 1] = 1;
                }
            }
        }
    }
    return 1;
}

//-----------------------------------------------------------------------------------------------------------

char check_solved_board(unsigned char solved_board[SIZE][SIZE]) {

    printf("Checking comptability to original board\n");
    
    for (int r = 0; r < SIZE; r++) {
        for (int c = 0; c < SIZE; c++) {
            if (solved_board[r][c]==0) {
                printf("FAIL: Solved board includes empty cells\n");
                return FALSE ;
            }
            else if (loaded_board[r][c]!=0) {
                  if (solved_board[r][c]!=loaded_board[r][c]){
                     printf("FAIL: solved board[%d][%d]=%d does not match loaded board[%d][%d]=%d\n",
                     r,c,solved_board[r][c],r,c,loaded_board[r][c]);
                     return FALSE ;
                  }
                }
        }
    }

    // Checking Sudoku rules compatibility
    char solved_legal = is_solved(solved_board) ;
    if (!solved_legal) printf("Solved board violates Sudoku rules\n");
    return solved_legal;
}


//-----------------------------------------------------------------------------------------------------------

void print_board(unsigned char board[SIZE][SIZE]) {
    for (int r = 0; r < SIZE; r++) {
        if (r % 3 == 0 && r != 0)
            printf(" ------+-------+------\n");
        for (int c = 0; c < SIZE; c++) {
            if (c % 3 == 0 && c != 0) printf(" |");
            printf(" %d", board[r][c]);
        }
        printf("\n");
    }
    printf("\n\n");   
}

//----------------------------------------------------------------