//常量定义

//所有指令编号
`define Lui    6'b000001
`define Auipc  6'b000010
`define Jal    6'b000011
`define Jalr   6'b000100
`define Beq    6'b000101
`define Bne    6'b000110
`define Blt    6'b000111
`define Bge    6'b001000
`define Bltu   6'b001001
`define Bgeu   6'b001010
`define Lb     6'b001011
`define Lh     6'b001100
`define Lw     6'b001101
`define Lbu    6'b001110
`define Lhu    6'b001111
`define Sb     6'b010000
`define Sh     6'b010001
`define Sw     6'b010010
`define Addi   6'b010011
`define Slti   6'b010100
`define Sltiu  6'b010101
`define Xori   6'b010110
`define Ori    6'b010111
`define Andi   6'b011000
`define Slli   6'b011001
`define Srli   6'b011010
`define Srai   6'b011011
`define Add    6'b011100
`define Sub    6'b011101
`define Sll    6'b011110
`define Slt    6'b011111
`define Sltu   6'b100000
`define Xor    6'b100001
`define Srl    6'b100010
`define Sra    6'b100011
`define Or     6'b100100
`define And    6'b100101
`define Exit   6'b100110

//用于decoder分析指令类型
`define Lui_ins   7'b0110111
`define Auipc_ins 7'b0010111
`define Jal_ins   7'b1101111
`define Jalr_ins  7'b1100111
`define L_ins     7'b0000011   //包括Lb,Lh,Lw,Lbu,Lhu
`define I_ins     7'b0010011   //包括Addi,Slti,Sltiu,Xori,Ori,Andi,Slli,Srai,Srli
`define B_ins     7'b1100011   //包括Beq,Bne,Blt,Bge,Bltu,Bgeu
`define S_ins     7'b0100011   //包括Sb,Sh,Sw
`define R_ins     7'b0110011   //包括Sub,Add,Sll,Slt,Sltu,Xor,Sra,Srl,Or,And

//ROB
`define RoB_addr 5
`define RoB_size 32

//RS
`define RS_addr 3
`define RS_size 8

//
`define LSB_addr 3
`define LSB_size 8