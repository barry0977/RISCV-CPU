`include "const.v"

module decoder(
    input wire clk_in,
    input wire rst_in,
    input wire rdy_in,

    input  wire [31:0] instr,
    input  wire [31:0] pc,

    //向RF获取寄存器依赖关系
    output wire rf_rs1,
    output wire rf_rs2,
    input  wire rf_val1,
    input  wire rf_val2,
    input  wire rf_has_rely1,
    input  wire rf_has_rely2,
    input  wire rf_rely1,
    input  wire rf_rely2,

    //给RoB
    input  wire rob_full,
    input  wire rob_index,//加入后在RoB中的序号
    output reg  rob_inst_valid,
    output reg  rob_inst_ready,
    output reg [2:0] rob_type,
    output reg [31:0] rob_value,
    output reg [4:0] rob_rd,
    output reg [31:0] rob_inst_pc,

    //给RS/LSB
    input  wire rs_full,
    output reg  rs_inst_valid,
    input  wire lsb_full,
    output reg  lsb_inst_valid,
    output reg [5:0] inst_op,
    output reg [`RoB_addr-1:0] RoB_index,
    output reg [31:0] inst_val1,
    output reg [31:0] inst_val2,
    output reg inst_has_rely1,
    output reg inst_has_rely2,
    output reg [`RoB_addr-1:0] rely1,
    output reg [`RoB_addr-1:0] rely2,
    output reg [31:0] inst_imm
);

wire [4:0] rd = instr[11:7];
wire [4:0] rs1 = instr[19:15];
wire [4:0] rs2 = instr[24:20];
wire [6:0] optype = instr[6:0];
wire [2:0] funct3 = instr[14:12];
wire [6:0] funct7 = instr[31:25];
wire [31:0] imm_U = {instr[31:12],12'b0};
wire [31:0] imm_J = {{12{instr[31]}},instr[19:12],instr[20],instr[30:21],1'b0};
wire [31:0] imm_I = {{20{instr[31]}},instr[31:20]};
wire [31:0] imm_B = {{20{instr[31]}},instr[7],instr[30:25],instr[11:8],1'b0};
wire [31:0] imm_S = {{20{instr[31]}},instr[31:25],instr[11:7]};


// always @(posedge clk_in)begin
//     case(optype)
//        `Lui_ins:begin
//             op <= `Lui;
//             imm <= {instr[31:12],12'b0};
//        end
//        `Auipc_ins:begin
//             op <= `Auipc;
//             imm <= {instr[31:12],12'b0};
//        end 
//        `Jal_ins:begin
//             op <= `Jal;
//             imm <= {{12{instr[31]}},instr[19:12],instr[20],instr[30:21],1'b0};
//        end
//        `Jalr_ins:begin
//             op <= `Jalr;
//             imm <= {{20{instr[31]}},instr[31:20]};
//        end
//        `L_ins:begin
//             case(funct3)
//                 3'b000:begin
//                     op <= `Lb;
//                 end
//                 3'b001:begin
//                     op <= `Lh;
//                 end
//                 3'b010:begin
//                     op <= `Lw;
//                 end
//                 3'b100:begin
//                     op <= `Lbu;
//                 end
//                 3'b101:begin
//                     op <= `Lhu;
//                 end
//             endcase
//             imm <= {{20{instr[31]}},instr[31:20]};
//        end
//        `I_ins:begin
//             case(funct3)
//                 3'b000:begin
//                     op <= `Addi;
//                 end
//                 3'b010:begin
//                     op <= `Slti;
//                 end
//                 3'b011:begin
//                     op <= `Sltiu;
//                 end
//                 3'b100:begin
//                     op <= `Xori;
//                 end
//                 3'b110:begin
//                     op <= `Ori;
//                 end
//                 3'b111:begin
//                     op <= `Andi;
//                 end
//                 3'b001:begin
//                     op <= `Slli;
//                 end
//                 3'b101:begin
//                     if(funct7[5])begin
//                         op <= `Srai;
//                     end else begin
//                         op  <=`Srli;
//                     end
//                 end
//             endcase
//             imm <= {{20{instr[31]}},instr[31:20]};
//        end
//        `B_ins:begin
//             case(funct3)
//                 3'b000:begin
//                     op <= `Beq;
//                 end
//                 3'b001:begin
//                     op <= `Bne;
//                 end
//                 3'b100:begin
//                     op <= `Blt;
//                 end
//                 3'b101:begin
//                     op <= `Bge;
//                 end
//                 3'b110:begin
//                     op <= `Bltu;
//                 end
//                 3'b111:begin
//                     op <= `Bgeu;
//                 end
//             endcase
//             imm <= {{20{instr[31]}},instr[7],instr[30:25],instr[11:8],1'b0};
//        end
//        `S_ins:begin
//             case(funct3)
//                 3'b000:begin
//                     op <= `Sb;
//                 end
//                 3'b001:begin
//                     op <= `Sh;
//                 end
//                 3'b010:begin
//                     op <= `Sw;
//                 end
//             endcase
//             imm <= {{20{instr[31]}},instr[31:25],instr[11:7]};
//        end
//        `R_ins:begin
//             case(funct3)
//                 3'b000:begin
//                     if(funct7[5])begin
//                         op <= `Sub;
//                     end else begin
//                         op <= `Add;
//                     end
//                 end
//                 3'b001:begin
//                     op <= `Sll;
//                 end
//                 3'b010:begin
//                     op <= `Slt;
//                 end
//                 3'b011:begin
//                     op <= `Sltu;
//                 end
//                 3'b100:begin
//                     op <= `Xor;
//                 end
//                 3'b101:begin
//                     if(funct7[5])begin
//                         op <= `Sra;
//                     end else begin
//                         op <= `Srl;
//                     end
//                 end
//                 3'b110:begin
//                     op <= `Or;
//                 end
//                 3'b111:begin
//                     op <= `And;
//                 end
//             endcase
//             imm <= 32'b0;
//        end
//     endcase
// end

always @(posedge clk_in)begin
    if(rst_in)begin
    end
    else if(rdy_in)begin
    end
end

endmodule
