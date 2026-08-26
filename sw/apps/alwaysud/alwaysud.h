#ifndef _ALWAYSUD_H_
#define _ALWAYSUD_H_

// MUST BE SAME AS HW

typedef union {
    uint32_t  full ;
    struct {
        uint32_t cmd    : 8;
        uint32_t unused : 24;        
    } part ;
} start_reg_t ;

typedef union {
    uint32_t  full ;
    struct {
        uint32_t status :  8;
        uint32_t result :  8;        
        uint32_t unused : 16;
    } part ;
} done_reg_t ;


#endif