`include "const.v"

module Cdecoder(
    input wire clk_in,
    input wire rst_in,
    input wire rdy_in,

    //从InsFetch获取指令
    input  wire if_valid,
    input  wire [31:0] instr,
    input  wire [31:0] pc,
    input  wire isjump,
    output wire stall, //是否有元件已满
    output wire dc_valid,
    output wire [31:0] dc_nextpc,

    //向RF获取寄存器依赖关系
    output wire [4:0] rf_rs1,
    output wire [4:0] rf_rs2,
    input  wire [31:0] rf_val1,
    input  wire [31:0] rf_val2,
    input  wire rf_has_rely1,
    input  wire rf_has_rely2,
    input  wire [`RoB_addr-1:0] rf_rely1,
    input  wire [`RoB_addr-1:0] rf_rely2,
    //向RoB询问是否更新(可能在同一周期RF还没更新，或者是Lui等指令不会进RS/LSB，因此要直接从RoB读取)
    output wire [`RoB_addr-1:0] rob_id1,
    output wire [`RoB_addr-1:0] rob_id2,
    input  wire rob_id1_ready,
    input  wire rob_id2_ready,
    input  wire [31:0] rob_id1_value,
    input  wire [31:0] rob_id2_value,

    //给RoB
    input  wire rob_clear,
    input  wire rob_full,
    input  wire [`RoB_addr-1:0] rob_index,//加入后在RoB中的序号
    output reg  rob_inst_valid,
    output reg  rob_inst_ready,
    output reg [5:0] rob_inst_op,
    output reg [2:0] rob_type,
    output reg [31:0] rob_value,
    output reg [4:0] rob_rd,
    output reg [31:0] rob_inst_pc,
    output reg [31:0] rob_addr,//用于记录branch指令的跳转地址
    output reg rob_isjump,

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
    output reg [`RoB_addr-1:0] inst_rely1,
    output reg [`RoB_addr-1:0] inst_rely2,
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
wire [31:0] imm_Ishamt = {27'b0,instr[24:20]};
wire [31:0] imm_B = {{20{instr[31]}},instr[7],instr[30:25],instr[11:8],1'b0};
wire [31:0] imm_S = {{20{instr[31]}},instr[31:25],instr[11:7]};

wire [5:0] opcode;
wire [2:0] robtype;
wire has_rs1,has_rs2;//是否使用rs1,rs2
wire [31:0] real_val1,real_val2;

reg [31:0] last_pc;

assign stall = rob_full || rs_full || lsb_full;

assign opcode = optype == `Lui_ins ? `Lui :
                optype == `Auipc_ins ? `Auipc :
                optype == `Jal_ins ? `Jal :
                optype == `Jalr_ins ? `Jalr :
                optype == `L_ins ? (funct3 == 3'b000 ? `Lb :
                                    funct3 == 3'b001 ? `Lh :
                                    funct3 == 3'b010 ? `Lw :
                                    funct3 == 3'b100 ? `Lbu : 
                                    funct3 == 3'b101 ? `Lhu : 0) :
                optype == `I_ins ? (funct3 == 3'b000 ? `Addi :
                                    funct3 == 3'b010 ? `Slti :
                                    funct3 == 3'b011 ? `Sltiu :
                                    funct3 == 3'b100 ? `Xori :
                                    funct3 == 3'b110 ? `Ori :
                                    funct3 == 3'b111 ? `Andi :
                                    funct3 == 3'b001 ? `Slli :
                                    funct3 == 3'b101 ? (funct7[5] ? `Srai : `Srli) : 0) :
                optype == `B_ins ? (funct3 == 3'b000 ? `Beq :
                                    funct3 == 3'b001 ? `Bne :
                                    funct3 == 3'b100 ? `Blt :
                                    funct3 == 3'b101 ? `Bge :
                                    funct3 == 3'b110 ? `Bltu :
                                    funct3 == 3'b111 ? `Bgeu : 0) :
                optype == `S_ins ? (funct3 == 3'b000 ? `Sb :
                                    funct3 == 3'b001 ? `Sh :
                                    funct3 == 3'b010 ? `Sw : 0) : 
                optype == `R_ins ? (funct3 == 3'b000 ? (funct7[5] ? `Sub : `Add) :
                                    funct3 == 3'b001 ? `Sll :
                                    funct3 == 3'b010 ? `Slt :
                                    funct3 == 3'b011 ? `Sltu :
                                    funct3 == 3'b100 ? `Xor :
                                    funct3 == 3'b101 ? (funct7[5] ? `Sra : `Srl) :
                                    funct3 == 3'b110 ? `Or :
                                    funct3 == 3'b111 ? `And : 0) : `Exit;

wire [1:0] ctype = instr[1:0]; //11-普通指令，其余为c扩展指令
wire is_cins = ctype != 2'b11;
wire [2:0] f3_c = instr[15:13];
wire [1:0] f2_c = instr[1:0];
wire [1:0] f2_c1 = instr[11:10];
wire [1:0] f2_c2 = instr[6:5];
wire [4:0] rs1_c1 = {2'b0,instr[9:7]};
wire [4:0] rs2_c1 = {2'b0,instr[4:2]};
wire [4:0] rs1_c2 = instr[11:7];
wire [4:0] rs2_c2 = instr[6:2];

wire [31:0] imm_J_c = {{21{instr[12]}},instr[8],instr[10:9],instr[6],instr[7],instr[2],instr[11],instr[5:3],1'b0};
wire [31:0] imm_B_c = {{24{instr[12]}},instr[6:5],instr[2],instr[11:10],instr[4:3],1'b0};
wire [31:0] imm_U_c = {{15{instr[12]}}, instr[6 : 2], 12'b0};

wire [4:0] c_opcode = is_cins ? (f2_c == 2'b00 ? (f3_c == 3'b000 ? `C_addi4spn :
                                                 f3_c == 3'b010 ? `C_lw :
                                                 f3_c == 3'b110 ? `C_sw : 0) :
                                 f2_c == 2'b01 ? (f3_c == 3'b000 ? `C_addi :
                                                 f3_c == 3'b001 ? `C_jal :
                                                 f3_c == 3'b010 ? `C_li : 
                                                 f3_c == 3'b011 ? (rs1_c2 == 2 ? `C_addi16sp : `C_lui) :
                                                 f3_c == 3'b100 ? (f2_c1 == 2'b00 ? `C_srli :
                                                                   f2_c1 == 2'b01 ? `C_srai :
                                                                   f2_c1 == 2'b10 ? `C_andi : (f2_c2 == 2'b00 ? `C_sub :
                                                                                               f2_c2 == 2'b01 ? `C_xor :
                                                                                               f2_c2 == 2'b10 ? `C_or : `C_and)) :
                                                 f3_c == 3'b101 ? `C_j :
                                                 f3_c == 3'b110 ? `C_beqz :
                                                 f3_c == 3'b111 ? `C_bnez : 0) :
                                 f2_c == 2'b10 ? (f3_c == 3'b000 ? `C_slli :
                                                 f3_c == 3'b010 ? `C_lwsp :
                                                 f3_c == 3'b100 ? (instr[12] == 0 ? (rs2_c2 == 0 ? `C_jr : `C_mv) :
                                                                                    (rs2_c2 == 0 ? `C_jalr : `C_add)) :
                                                 f3_c == 3'b110 ? `C_swsp : 0) : 0) : 0;

wire [4:0] rs1_c = c_opcode == `C_addi ? rs1_c2 :
                   c_opcode == `C_jal ? 0 :
                   c_opcode == `C_li ? 0 :
                   c_opcode == `C_addi16sp ? 2 :
                   c_opcode == `C_lui ? 0 :
                   c_opcode == `C_srli ? rs1_c1 + 5'd8 :
                   c_opcode == `C_srai ? rs1_c1 + 5'd8 :
                   c_opcode == `C_andi ? rs1_c1 + 5'd8 :
                   c_opcode == `C_sub ? rs1_c1 + 5'd8 :
                   c_opcode == `C_xor ? rs1_c1 + 5'd8 :
                   c_opcode == `C_or ? rs1_c1 + 5'd8 :
                   c_opcode == `C_and ? rs1_c1 + 5'd8 :
                   c_opcode == `C_j ? 0 :
                   c_opcode == `C_beqz ? rs1_c1 + 5'd8 :
                   c_opcode == `C_bnez ? rs1_c1 + 5'd8 :
                   c_opcode == `C_addi4spn ? 2 :
                   c_opcode == `C_lw ? rs1_c1 + 5'd8 :
                   c_opcode == `C_sw ? rs1_c1 + 5'd8 :
                   c_opcode == `C_slli ? rs1_c2 :
                   c_opcode == `C_jr ? rs1_c2 :
                   c_opcode == `C_mv ? 0 :
                   c_opcode == `C_jalr ? rs1_c2 :
                   c_opcode == `C_add ? rs1_c2 :
                   c_opcode == `C_lwsp ? 2 :
                   c_opcode == `C_swsp ? 2 : 0;

wire [4:0] rs2_c = c_opcode == `C_addi ? 0 :
                   c_opcode == `C_jal ? 0 :
                   c_opcode == `C_li ? 0 :
                   c_opcode == `C_addi16sp ? 0 :
                   c_opcode == `C_lui ? 0 :
                   c_opcode == `C_srli ? 0 :
                   c_opcode == `C_srai ? 0 :
                   c_opcode == `C_andi ? 0 :
                   c_opcode == `C_sub ? rs2_c1 + 5'd8 :
                   c_opcode == `C_xor ? rs2_c1 + 5'd8 :
                   c_opcode == `C_or ? rs2_c1 + 5'd8 :
                   c_opcode == `C_and ? rs2_c1 + 5'd8 :
                   c_opcode == `C_j ? 0 :
                   c_opcode == `C_beqz ? 0 :
                   c_opcode == `C_bnez ? 0 :
                   c_opcode == `C_addi4spn ? 0 :
                   c_opcode == `C_lw ? 0 :
                   c_opcode == `C_sw ? rs2_c1 + 5'd8 :
                   c_opcode == `C_slli ? 0 :
                   c_opcode == `C_jr ? 0 :
                   c_opcode == `C_mv ? rs2_c2 :
                   c_opcode == `C_jalr ? 0 :
                   c_opcode == `C_add ? rs2_c2 :
                   c_opcode == `C_lwsp ? 0 :
                   c_opcode == `C_swsp ? rs2_c2 : 0;

assign robtype = (opcode >= `Lui && opcode <= `Jalr) ? `else_ : opcode <= `Bgeu ? `branch_ : opcode <= `Lhu ? `load_ : opcode <= `Sw ? `store_ : opcode <= `And ? `toreg_ : `exit_;
assign has_rs1 = (opcode != `Lui) && (opcode != `Auipc) && (opcode != `Jal) ? 1 : 0;
assign has_rs2 = (optype == `B_ins) || (optype == `S_ins) || (optype == `R_ins) ? 1 : 0;
assign rf_rs1 = !is_cins ? rs1 : rs1_c2;
assign rf_rs2 = !is_cins ? rs2 : rs2_c2;
assign rob_id1 = rf_rely1;
assign rob_id2 = rf_rely2;
assign real_val1 = (!rf_has_rely1) ? rf_val1 : (rob_id1_ready ? rob_id1_value : 0);
assign real_val2 = (!rf_has_rely2) ? rf_val2 : (rob_id2_ready ? rob_id2_value : 0);

assign dc_valid = if_valid && (last_pc != pc) && !stall;
assign dc_nextpc = !is_cins ? (optype == `Jal_ins ? pc + imm_J : (optype == `B_ins && isjump) ? pc + imm_B : pc + 4) : ((c_opcode == `C_jal || c_opcode == `C_j) ? pc + imm_J_c : ((c_opcode == `C_beqz || c_opcode == `C_bnez) && isjump) ? pc + imm_B_c : pc + 2);

always @(posedge clk_in)begin
    if(rst_in || rob_clear)begin //分支预测错误时要把此时收到的指令清空
        rob_inst_valid <= 0;
        rob_inst_ready <= 0;
        rob_inst_op <= 0;
        rob_type <= 0;
        rob_value <= 0;
        rob_rd <= 0;
        rob_inst_pc <= 0;
        rs_inst_valid <= 0;
        lsb_inst_valid <= 0;
        inst_op <= 0;
        RoB_index <= 0;
        inst_val1 <= 0;
        inst_val2 <= 0;
        inst_has_rely1 <= 0;
        inst_has_rely2 <= 0;
        inst_rely1 <= 0;
        inst_rely2 <= 0;
        inst_imm <= 0;
        last_pc <= 32'hffffffff;
    end
    else if(rdy_in)begin
        if(if_valid && !stall)begin
            rob_inst_valid <= 1;
            rob_inst_pc <= pc;
            
            RoB_index <= rob_index;
            last_pc <= pc;
            if(!is_cins)begin //普通指令
                rob_inst_op <= opcode;
                rob_type <= robtype;
                inst_val1 <= has_rs1 ? real_val1 : 0;
                inst_val2 <= has_rs2 ? real_val2 : ((funct3 == 3'b001 || funct3 == 3'b101) ? imm_Ishamt : imm_I);
                inst_has_rely1 <= has_rs1 && rf_has_rely1 && !rob_id1_ready;
                inst_has_rely2 <= has_rs2 && rf_has_rely2 && !rob_id2_ready;
                inst_rely1 <= rf_rely1;
                inst_rely2 <= rf_rely2;
                inst_op <= opcode;

                if(optype == `L_ins || optype == `S_ins)begin
                    rob_inst_ready <= 0;
                    lsb_inst_valid <= 1;
                    rs_inst_valid <= 0;
                    rob_value <= 0;
                    if(optype == `L_ins)begin
                        rob_rd <= rd;
                        inst_imm <= 0;
                    end
                    else begin
                        rob_rd <= 0;
                        inst_imm <= imm_S;
                    end
                    rob_addr <= 0;
                    rob_isjump <= 0;
                end
                else begin
                    inst_imm <= 0;
                    if(optype == `Lui_ins)begin
                        rob_inst_ready <= 1;
                        lsb_inst_valid <= 0;
                        rs_inst_valid <= 0;
                        rob_value <= imm_U;
                        rob_rd <= rd;
                        rob_addr <= 0;
                        rob_isjump <= 0;
                    end
                    else if(optype == `Auipc_ins)begin
                        rob_inst_ready <= 1;
                        lsb_inst_valid <= 0;
                        rs_inst_valid <= 0;
                        rob_value <= imm_U + pc;
                        rob_rd <= rd;
                        rob_addr <= 0;
                        rob_isjump <= 0;
                    end
                    else if(optype == `Jal_ins)begin
                        rob_inst_ready <= 1;
                        lsb_inst_valid <= 0;
                        rs_inst_valid <= 0;
                        rob_value <= pc + 4;
                        rob_rd <= rd;
                        rob_addr <= 0;
                        rob_isjump <= 1;
                    end
                    else if(optype == `Jalr_ins)begin
                        rob_inst_ready <= 0;
                        lsb_inst_valid <= 0;
                        rs_inst_valid <= 1;
                        rob_value <= pc + 4;
                        rob_rd <= rd;
                        rob_addr <= 0;
                        rob_isjump <= 1;
                    end
                    else if(optype == `B_ins)begin
                        rob_inst_ready <= 0;
                        lsb_inst_valid <= 0;
                        rs_inst_valid <= 1;
                        rob_value <= 0;
                        rob_rd <= 0;
                        rob_addr <= pc + imm_B;
                        rob_isjump <= isjump;
                    end
                    else begin
                        rob_inst_ready <= 0;
                        lsb_inst_valid <= 0;
                        rs_inst_valid <= 1;
                        rob_value <= 0;
                        rob_rd <= rd;
                        rob_addr <= 0;
                        rob_isjump <= 0;
                    end
                end
            end
            else begin//c扩展指令
                inst_rely1 <= rf_rely1;
                inst_rely2 <= rf_rely2;
                if(ctype == 2'b00)begin
                    case(instr[15:13])
                        3'b000:begin //c.addi4spn
                            rob_inst_op <= `Addi;
                            rob_type <= `toreg_;
                            inst_op <= `Addi;
                            rob_inst_ready <= 0;
                            lsb_inst_valid <= 0;
                            rs_inst_valid <= 1;
                            rob_value <= 0;
                            rob_rd <= rs2_c1 + 5'd8;
                            rob_addr <= 0;
                            rob_isjump <= 0;
                            inst_imm <= 0;
                            inst_val1 <= real_val1;
                            inst_val2 <= {22'b0,instr[10:7],instr[12:11],instr[5],instr[6],2'b0};
                            inst_has_rely1 <= rf_has_rely1 && !rob_id1_ready;
                            inst_has_rely2 <= 0;
                        end
                        3'b010:begin //c.lw
                            rob_inst_op <= `Lw;
                            rob_type <= `load_;
                            inst_op <= `Lw;
                            rob_inst_ready <= 0;
                            lsb_inst_valid <= 1;
                            rs_inst_valid <= 0;
                            rob_value <= 0;
                            rob_rd <= rs2_c1 + 5'd8;
                            rob_addr <= 0;
                            rob_isjump <= 0;
                            inst_imm <= 0;
                            inst_val1 <= real_val1;
                            inst_val2 <= {25'b0,instr[5],instr[12:10],instr[6],2'b0};
                            inst_has_rely1 <= rf_has_rely1 && !rob_id1_ready;
                            inst_has_rely2 <= 0;
                        end
                        3'b110:begin //c.sw
                            rob_inst_op <= `Sw;
                            rob_type <= `store_;
                            inst_op <= `Sw;
                            rob_inst_ready <= 0;
                            lsb_inst_valid <= 1;
                            rs_inst_valid <= 0;
                            rob_value <= 0;
                            rob_rd <= 0;
                            rob_addr <= 0;
                            rob_isjump <= 0;
                            inst_imm <= {25'd0,instr[5],instr[12:10],instr[6],2'b00};
                            inst_val1 <= real_val1;
                            inst_val2 <= real_val2;
                            inst_has_rely1 <= rf_has_rely1 && !rob_id1_ready;
                            inst_has_rely2 <= rf_has_rely2 && !rob_id2_ready;
                        end
                    endcase
                end
                else if(ctype == 2'b01)begin
                    case(instr[15:13])
                        3'b000:begin //c.addi
                            rob_inst_op <= `Addi;
                            rob_type <= `toreg_;
                            inst_op <= `Addi;
                            rob_inst_ready <= 0;
                            lsb_inst_valid <= 0;
                            rs_inst_valid <= 1;
                            rob_value <= 0;
                            rob_rd <= rs1_c2;
                            rob_addr <= 0;
                            rob_isjump <= 0;
                            inst_imm <= 0;
                            inst_val1 <= real_val1;
                            inst_val2 <= {{27{instr[12]}}, instr[6 : 2]};
                            inst_has_rely1 <= rf_has_rely1 && !rob_id1_ready;
                            inst_has_rely2 <= 0;
                        end
                        3'b001:begin //c.jal
                            rob_inst_op <= `Jal;
                            rob_type <= `else_;
                            inst_op <= `Jal;
                            rob_inst_ready <= 1;
                            lsb_inst_valid <= 0;
                            rs_inst_valid <= 0;
                            rob_value <= pc + 2;
                            rob_rd <= 1;
                            rob_addr <= 0;
                            rob_isjump <= 1;
                            inst_imm <= 0;
                            inst_val1 <= 0;
                            inst_val2 <= 0;
                            inst_has_rely1 <= 0;
                            inst_has_rely2 <= 0;
                        end
                        3'b010:begin //c.li
                            rob_inst_op <= `Addi;
                            rob_type <= `toreg_;
                            inst_op <= `Addi;
                            rob_inst_ready <= 0;
                            lsb_inst_valid <= 0;
                            rs_inst_valid <= 1;
                            rob_value <= 0;
                            rob_rd <= rs1_c2;
                            rob_addr <= 0;
                            rob_isjump <= 0;
                            inst_imm <= 0;
                            inst_val1 <= 0;
                            inst_val2 <= {{27{instr[12]}}, instr[6 : 2]};
                            inst_has_rely1 <= 0;
                            inst_has_rely2 <= 0;
                        end
                        3'b011:begin
                            if(instr[11:7] == 2)begin //c.addi16sp
                                rob_inst_op <= `Addi;
                                rob_type <= `toreg_;
                                inst_op <= `Addi;
                                rob_inst_ready <= 0;
                                lsb_inst_valid <= 0;
                                rs_inst_valid <= 1;
                                rob_value <= 0;
                                rob_rd <= 2;
                                rob_addr <= 0;
                                rob_isjump <= 0;
                                inst_imm <= 0;
                                inst_val1 <= real_val1;
                                inst_val2 <= {{23{instr[12]}},instr[4:3],instr[5],instr[2],instr[6],4'b0};
                                inst_has_rely1 <= rf_has_rely1 && !rob_id1_ready;
                                inst_has_rely2 <= 0;
                            end
                            else begin //c.lui
                                rob_inst_op <= `Lui;
                                rob_type <= `else_;
                                inst_op <= `Lui;
                                rob_inst_ready <= 1;
                                lsb_inst_valid <= 0;
                                rs_inst_valid <= 0;
                                rob_value <= imm_U_c;
                                rob_rd <= rs1_c2;
                                rob_addr <= 0;
                                rob_isjump <= 0;
                                inst_imm <= 0;
                                inst_val1 <= 0;
                                inst_val2 <= 0;
                                inst_has_rely1 <= 0;
                                inst_has_rely2 <= 0;
                            end
                        end
                        3'b100:begin
                            if(instr[11:10] == 2'b00)begin //c.srli
                                rob_inst_op <= `Srli;
                                rob_type <= `toreg_;
                                inst_op <= `Srli;
                                rob_inst_ready <= 0;
                                lsb_inst_valid <= 0;
                                rs_inst_valid <= 1;
                                rob_value <= 0;
                                rob_rd <= rs1_c1 + 5'd8;
                                rob_addr <= 0;
                                rob_isjump <= 0;
                                inst_imm <= 0;
                                inst_val1 <= real_val1;
                                inst_val2 <= {26'b0,instr[12], instr[6 : 2]};
                                inst_has_rely1 <= rf_has_rely1 && !rob_id1_ready;
                                inst_has_rely2 <= 0;
                            end
                            else if(instr[11:10] == 2'b01)begin //c.srai
                                rob_inst_op <= `Srai;
                                rob_type <= `toreg_;
                                inst_op <= `Srai;
                                rob_inst_ready <= 0;
                                lsb_inst_valid <= 0;
                                rs_inst_valid <= 1;
                                rob_value <= 0;
                                rob_rd <= rs1_c1 + 5'd8;
                                rob_addr <= 0;
                                rob_isjump <= 0;
                                inst_imm <= 0;
                                inst_val1 <= real_val1;
                                inst_val2 <= {26'b0,instr[12], instr[6 : 2]};
                                inst_has_rely1 <= rf_has_rely1 && !rob_id1_ready;
                                inst_has_rely2 <= 0;
                            end
                            else if(instr[11:10] == 2'b10)begin //c.andi 
                                rob_inst_op <= `Andi;
                                rob_type <= `toreg_;
                                inst_op <= `Andi;
                                rob_inst_ready <= 0;
                                lsb_inst_valid <= 0;
                                rs_inst_valid <= 1;
                                rob_value <= 0;
                                rob_rd <= rs1_c1 + 5'd8;
                                rob_addr <= 0;
                                rob_isjump <= 0;
                                inst_imm <= 0;
                                inst_val1 <= real_val1;
                                inst_val2 <= {{27{instr[12]}}, instr[6 : 2]};
                                inst_has_rely1 <= rf_has_rely1 && !rob_id1_ready;
                                inst_has_rely2 <= 0;
                            end
                            else begin
                                rob_inst_ready <= 0;
                                lsb_inst_valid <= 0;
                                rs_inst_valid <= 1;
                                rob_value <= 0;
                                rob_rd <= rs1_c1 + 5'd8;
                                rob_addr <= 0;
                                rob_isjump <= 0;
                                inst_imm <= 0;
                                inst_val1 <= real_val1;
                                inst_val2 <= real_val2;
                                inst_has_rely1 <= rf_has_rely1 && !rob_id1_ready;
                                inst_has_rely2 <= rf_has_rely2 && !rob_id2_ready;
                                if(instr[6:5] == 2'b00)begin //c.sub
                                    rob_inst_op <= `Sub;
                                    rob_type <= `toreg_;
                                    inst_op <= `Sub;
                                end
                                else if(instr[6:5] == 2'b01)begin //c.xor
                                    rob_inst_op <= `Xor;
                                    rob_type <= `toreg_;
                                    inst_op <= `Xor;
                                end
                                else if(instr[6:5] == 2'b10)begin //c.or
                                    rob_inst_op <= `Or;
                                    rob_type <= `toreg_;
                                    inst_op <= `Or;
                                end
                                else begin //c.and
                                    rob_inst_op <= `And;
                                    rob_type <= `toreg_;
                                    inst_op <= `And;
                                end
                            end
                        end
                        3'b101:begin //c.j
                            rob_inst_op <= `Jal;
                            rob_type <= `else_;
                            inst_op <= `Jal;
                            rob_inst_ready <= 1;
                            lsb_inst_valid <= 0;
                            rs_inst_valid <= 0;
                            rob_value <= pc + 2;
                            rob_rd <= 0;
                            rob_addr <= 0;
                            rob_isjump <= 1;
                            inst_imm <= 0;
                            inst_val1 <= 0;
                            inst_val2 <= 0;
                            inst_has_rely1 <= 0;
                            inst_has_rely2 <= 0;
                        end 
                        3'b110:begin //c.beqz
                            rob_inst_op <= `Beq;
                            rob_type <= `branch_;
                            inst_op <= `Beq;
                            rob_inst_ready <= 0;
                            lsb_inst_valid <= 0;
                            rs_inst_valid <= 1;
                            rob_value <= 0;
                            rob_rd <= 0;
                            rob_addr <= pc + imm_B_c;
                            rob_isjump <= isjump;
                            inst_imm <= 0;
                            inst_val1 <= real_val1;
                            inst_val2 <= 0;
                            inst_has_rely1 <= rf_has_rely1 && !rob_id1_ready;
                            inst_has_rely2 <= 0;
                        end
                        3'b111:begin //c.bnez
                            rob_inst_op <= `Bne;
                            rob_type <= `branch_;
                            inst_op <= `Bne;
                            rob_inst_ready <= 0;
                            lsb_inst_valid <= 0;
                            rs_inst_valid <= 1;
                            rob_value <= 0;
                            rob_rd <= 0;
                            rob_addr <= pc + imm_B_c;
                            rob_isjump <= isjump;
                            inst_imm <= 0;
                            inst_val1 <= real_val1;
                            inst_val2 <= 0;
                            inst_has_rely1 <= rf_has_rely1 && !rob_id1_ready;
                            inst_has_rely2 <= 0;
                        end
                    endcase
                end
                else if(ctype == 2'b10)begin
                    case(instr[15:13])
                        3'b000:begin //c.slli
                            rob_inst_op <= `Slli;
                            rob_type <= `toreg_;
                            inst_op <= `Slli;
                            rob_inst_ready <= 0;
                            lsb_inst_valid <= 0;
                            rs_inst_valid <= 1;
                            rob_value <= 0;
                            rob_rd <= rs1_c2;
                            rob_addr <= 0;
                            rob_isjump <= 0;
                            inst_imm <= 0;
                            inst_val1 <= real_val1;
                            inst_val2 <= {26'b0,instr[12], instr[6 : 2]};
                            inst_has_rely1 <= rf_has_rely1 && !rob_id1_ready;
                            inst_has_rely2 <= 0;
                        end
                        3'b010:begin //c.lwsp
                            rob_inst_op <= `Lw;
                            rob_type <= `load_;
                            inst_op <= `Lw;
                            rob_inst_ready <= 0;
                            lsb_inst_valid <= 1;
                            rs_inst_valid <= 0;
                            rob_value <= 0;
                            rob_rd <= rs1_c2;
                            rob_addr <= 0;
                            rob_isjump <= 0;
                            inst_imm <= 0;
                            inst_val1 <= real_val1;
                            inst_val2 <= {24'b0,instr[3:2],instr[12],instr[6:4],2'b0};
                            inst_has_rely1 <= rf_has_rely1 && !rob_id1_ready;
                            inst_has_rely2 <= 0;
                        end
                        3'b100:begin
                            if(instr[12] == 0)begin
                                if(instr[6:2] == 0)begin //c.jr
                                    rob_inst_op <= `Jalr;
                                    rob_type <= `else_;
                                    inst_op <= `Jalr;
                                    rob_inst_ready <= 0;
                                    lsb_inst_valid <= 0;
                                    rs_inst_valid <= 1;
                                    rob_value <= pc + 2;
                                    rob_rd <= 0;
                                    rob_addr <= 0;
                                    rob_isjump <= 1;
                                    inst_imm <= 0;
                                    inst_val1 <= real_val1;
                                    inst_val2 <= 0;
                                    inst_has_rely1 <= rf_has_rely1 && !rob_id1_ready;
                                    inst_has_rely2 <= 0;
                                end
                                else begin //c.mv
                                    rob_inst_op <= `Add;
                                    rob_type <= `toreg_;
                                    inst_op <= `Add;
                                    rob_inst_ready <= 0;
                                    lsb_inst_valid <= 0;
                                    rs_inst_valid <= 1;
                                    rob_value <= 0;
                                    rob_rd <= rs1_c2;
                                    rob_addr <= 0;
                                    rob_isjump <= 0;
                                    inst_imm <= 0;
                                    inst_val1 <= 0;
                                    inst_val2 <= real_val2;
                                    inst_has_rely1 <= 0;
                                    inst_has_rely2 <= rf_has_rely2 && !rob_id2_ready;
                                end
                            end
                            else begin
                                if(instr[6:2] == 0)begin //c.jalr
                                    rob_inst_op <= `Jalr;
                                    rob_type <= `else_;
                                    inst_op <= `Jalr;
                                    rob_inst_ready <= 0;
                                    lsb_inst_valid <= 0;
                                    rs_inst_valid <= 1;
                                    rob_value <= pc + 2;
                                    rob_rd <= 1;
                                    rob_addr <= 0;
                                    rob_isjump <= 1;
                                    inst_imm <= 0;
                                    inst_val1 <= real_val1;
                                    inst_val2 <= 0;
                                    inst_has_rely1 <= rf_has_rely1 && !rob_id1_ready;
                                    inst_has_rely2 <= 0;
                                end
                                else begin //c.add
                                    rob_inst_op <= `Add;
                                    rob_type <= `toreg_;
                                    inst_op <= `Add;
                                    rob_inst_ready <= 0;
                                    lsb_inst_valid <= 0;
                                    rs_inst_valid <= 1;
                                    rob_value <= 0;
                                    rob_rd <= rs1_c2;
                                    rob_addr <= 0;
                                    rob_isjump <= 0;
                                    inst_imm <= 0;
                                    inst_val1 <= real_val1;
                                    inst_val2 <= real_val2;
                                    inst_has_rely1 <= rf_has_rely1 && !rob_id1_ready;
                                    inst_has_rely2 <= rf_has_rely2 && !rob_id2_ready;
                                end
                            end
                        end
                        3'b110:begin //c.swsp
                            rob_inst_op <= `Sw;
                            rob_type <= `store_;
                            inst_op <= `Sw;
                            rob_inst_ready <= 0;
                            lsb_inst_valid <= 1;
                            rs_inst_valid <= 0;
                            rob_value <= 0;
                            rob_rd <= 0;
                            rob_addr <= 0;
                            rob_isjump <= 0;
                            inst_imm <= {24'b0,instr[8:7],instr[12:9],2'b0};
                            inst_val1 <= real_val1;
                            inst_val2 <= real_val2;
                            inst_has_rely1 <= rf_has_rely1 && !rob_id1_ready;
                            inst_has_rely2 <= rf_has_rely2 && !rob_id2_ready;
                        end
                    endcase
                end
            end
        end
        else begin
            rob_inst_valid <= 0;
            rs_inst_valid <= 0;
            lsb_inst_valid <= 0;
        end
    end
end
endmodule
