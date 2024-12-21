`include "const.v"

module decoder(
    input wire clk_in,
    input wire rst_in,
    input wire rdy_in,

    //从InsFetch获取指令
    input  wire if_valid,
    input  wire [31:0] instr,
    input  wire [31:0] pc,
    input  wire isjump,
    output wire stall, //是否有元件已满
    output reg  dc_valid,
    output reg [31:0] dc_nextpc,

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

assign stall = rob_full || rs_full || lsb_full;

assign opcode = optype == `Lui_ins ? `Lui :
                optype == `Auipc_ins ? `Auipc :
                optype == `Jal_ins ? `Jal :
                optype == `Jalr_ins ? `Jal :
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
assign robtype = (opcode >= `Lui && opcode <= `Jalr) ? `else_ : opcode <= `Bgeu ? `branch_ : opcode <= `Lhu ? `load_ : opcode <= `Sw ? `store_ : opcode <= `And ? `toreg_ : `exit_;
assign has_rs1 = (opcode != `Lui) && (opcode != `Auipc) && (opcode != `Jal) ? 1 : 0;
assign has_rs2 = (optype == `B_ins) && (optype == `S_ins) && (optype == `R_ins) ? 1 : 0;
assign rf_rs1 = rs1;
assign rf_rs2 = rs2;
assign rob_id1 = rf_rely1;
assign rob_id2 = rf_rely2;
assign real_val1 = (!rf_has_rely1) ? rf_val1 : (rob_id1_ready ? rob_id1_value : 0);
assign real_val2 = (!rf_has_rely2) ? rf_val2 : (rob_id2_ready ? rob_id2_value : 0);


always @(posedge clk_in)begin
    if(rst_in)begin
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
        dc_nextpc <= 0;
        dc_valid <= 0;
    end
    else if(rdy_in)begin
        if(if_valid && !stall)begin
            rob_inst_valid <= 1;
            rob_inst_pc <= pc;
            rob_inst_op <= opcode;
            rob_type <= robtype;

            inst_val1 <= has_rs1 ? real_val1 : 0;
            inst_val2 <= has_rs2 ? real_val2 : ((funct3 == 3'b001 || funct3 == 3'b101) ? imm_Ishamt : imm_I);
            inst_has_rely1 <= has_rs1 && rf_has_rely1 && !rob_id1_ready;
            inst_has_rely2 <= has_rs2 && rf_has_rely2 && !rob_id2_ready;
            inst_rely1 <= rf_rely1;
            inst_rely2 <= rf_rely2;
            inst_op <= opcode;
            RoB_index <= rob_index;
            dc_valid <= 1;
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
                dc_nextpc <= pc + 4;
            end
            else begin
                inst_imm <= 0;
                if(opcode == `Lui)begin
                    rob_inst_ready <= 1;
                    lsb_inst_valid <= 0;
                    rs_inst_valid <= 0;
                    rob_value <= imm_U;
                    rob_rd <= rd;
                    rob_addr <= 0;
                    rob_isjump <= 0;
                    dc_nextpc <= pc + 4;
                end
                else if(opcode == `Auipc)begin
                    rob_inst_ready <= 1;
                    lsb_inst_valid <= 0;
                    rs_inst_valid <= 0;
                    rob_value <= imm_U + pc;
                    rob_rd <= rd;
                    rob_addr <= 0;
                    rob_isjump <= 0;
                    dc_nextpc <= pc + 4;
                end
                else if(opcode == `Jal)begin
                    rob_inst_ready <= 1;
                    lsb_inst_valid <= 0;
                    rs_inst_valid <= 0;
                    rob_value <= pc + 4;
                    rob_rd <= rd;
                    rob_addr <= 0;
                    rob_isjump <= 1;
                    dc_nextpc <= pc + imm_J;
                end
                else if(opcode == `Jalr)begin
                    rob_inst_ready <= 0;
                    lsb_inst_valid <= 0;
                    rs_inst_valid <= 1;
                    rob_value <= pc + 4;
                    rob_rd <= rd;
                    rob_addr <= 0;
                    rob_isjump <= 1;
                    dc_nextpc <= pc + 4;
                end
                else if(optype == `B_ins)begin
                    rob_inst_ready <= 0;
                    lsb_inst_valid <= 0;
                    rs_inst_valid <= 1;
                    rob_value <= 0;
                    rob_rd <= rd;
                    rob_addr <= pc + imm_B;
                    rob_isjump <= isjump;
                    if(isjump)begin //预测跳转
                        dc_nextpc <= pc + imm_B;
                    end
                    else begin //预测不跳转
                        dc_nextpc <= pc + 4;
                    end
                end
                else begin
                    rob_inst_ready <= 0;
                    lsb_inst_valid <= 0;
                    rs_inst_valid <= 1;
                    rob_value <= 0;
                    rob_rd <= rd;
                    rob_addr <= 0;
                    rob_isjump <= 0;
                    dc_nextpc <= pc + 4;
                end
            end
        end
        else begin
            dc_valid <= 0;
            dc_nextpc <= 0;
        end
    end
end
endmodule
