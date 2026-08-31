#ifndef _SUD_LIB_H_
#define _SUD_LIB_H_

#include <k5_libs.h>

//-------------------------------------------------------------------------------------------------------------

#define SIZE 9

//-------------------------------------------------------------------------------------------------------------


void load_sud_board(unsigned char board[SIZE][SIZE]) ;

char check_solved_board(unsigned char solved_board[SIZE][SIZE]) ;

void print_board(unsigned char board[SIZE][SIZE]) ;

//----------------------------------------------------------------------------------------------------------

#endif