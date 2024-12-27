`include "./const.v"
// RISCV32 CPU top module
// port modification allowed for debugging purposes

module cpu(
  input  wire                 clk_in,			// system clock signal
  input  wire                 rst_in,			// reset signal
	input  wire					        rdy_in,			// ready signal, pause cpu when low

  input  wire [ 7:0]          mem_din,		// data input bus
  output wire [ 7:0]          mem_dout,		// data output bus
  output wire [31:0]          mem_a,			// address bus (only 17:0 is used)
  output wire                 mem_wr,			// write/read signal (1 for write)
	
	input  wire                 io_buffer_full, // 1 if uart buffer is full
	
	output wire [31:0]			dbgreg_dout		// cpu register output (debugging demo)
);

// implementation goes here

// Specifications:
// - Pause cpu(freeze pc, registers, etc.) when rdy_in is low
// - Memory read result will be returned in the next cycle. Write takes 1 cycle(no need to wait)
// - Memory is of size 128KB, with valid address ranging from 0x0 to 0x20000
// - I/O port is mapped to address higher than 0x30000 (mem_a[17:16]==2'b11)
// - 0x30000 read: read a byte from input
// - 0x30000 write: write a byte to output (write 0x00 is ignored)
// - 0x30004 read: read clocks passed since cpu starts (in dword, 4 bytes)
// - 0x30004 write: indicates program stop (will output '\0' through uart tx)

//CDB
wire flush;//清空信号
wire alu_valid;
wire [`RoB_addr-1:0] alu_robid;
wire [31:0] alu_val;
wire lsb_valid;
wire [`RoB_addr-1:0] lsb_robid;
wire [31:0] lsb_val;

//MemoryController & ICache
wire Mem_IC_ic_mem_ask;
wire [31:0] Mem_IC_ic_mem_addr;
wire Mem_IC_ic_mem_valid;
wire [31:0] Mem_IC_ic_mem_inst;

//MemoryController & LSB
wire Mem_LSB_lsb_request;
wire Mem_LSB_lsb_lors;
wire [5:0] Mem_LSB_lsb_mem_op;
wire [31:0] Mem_LSB_lsb_mem_addr;
wire [31:0] Mem_LSB_lsb_mem_data;
wire Mem_LSB_lsb_mem_valid;
wire [31:0] Mem_LSB_lsb_mem_val;

//ICache & InsFetch
wire IC_IF_fetch_valid;
wire [31:0] IC_IF_fetch_pc;
wire IC_IF_hit;
wire [31:0] IC_IF_hit_inst;

//InsFetch & ROB
wire [31:0] IF_ROB_rob_newpc;

//InsFetch & Predictor
wire IF_Pre_jump;
wire [31:0] IF_Pre_pc_to_pre;

//Predictor & ROB
wire Pre_ROB_rob_valid;
wire [31:0] Pre_ROB_rob_now_pc;
wire Pre_ROB_should_jump;

//Decoder & InsFetch
wire DC_IF_stall;
wire DC_IF_if_valid;
wire [31:0] DC_IF_if_inst;
wire [31:0] DC_IF_if_pc;
wire DC_IF_if_isjump;
wire DC_IF_dc_valid;
wire [31:0] DC_IF_dc_nextpc;

//Decoder & RF
wire [4:0] DC_RF_rs1_id;
wire [4:0] DC_RF_rs2_id;
wire [31:0] DC_RF_val1;
wire [31:0] DC_RF_val2;
wire DC_RF_has_rely1;
wire DC_RF_has_rely2;
wire [`RoB_addr-1:0] DC_RF_get_rely1;
wire [`RoB_addr-1:0] DC_RF_get_rely2;

//Decoder & ROB
wire [`RoB_addr-1:0] DC_ROB_rob_id1;
wire [`RoB_addr-1:0] DC_ROB_rob_id2;
wire DC_ROB_rob_id1_ready;
wire DC_ROB_rob_id2_ready;
wire [31:0] DC_ROB_rob_id1_value;
wire [31:0] DC_ROB_rob_id2_value;

wire DC_ROB_rob_full;
wire [`RoB_addr-1:0] DC_ROB_rob_index;
wire DC_ROB_rob_inst_valid;
wire DC_ROB_rob_inst_ready;
wire [5:0] DC_ROB_inst_op;
wire [2:0] DC_ROB_rob_type;
wire [31:0] DC_ROB_rob_value;
wire [4:0] DC_ROB_rob_rd;
wire [31:0] DC_ROB_rob_inst_pc;
wire [31:0] DC_ROB_rob_addr;
wire DC_ROB_rob_isjump;

//Decoder & RS/LSB
wire DC_RS_full;
wire DC_RS_inst_valid;
wire DC_LSB_full;
wire DC_LSB_inst_valid;
wire [5:0] DC_inst_op;
wire [`RoB_addr-1:0] DC_RoBindex;
wire [31:0] DC_inst_val1;
wire [31:0] DC_inst_val2;
wire DC_inst_has_rely1;
wire DC_inst_has_rely2;
wire [`RoB_addr-1:0] DC_inst_rely1;
wire [`RoB_addr-1:0] DC_inst_rely2;
wire [31:0] DC_inst_imm;

//RS & ALU
wire [31:0] RS_ALU_rs1;
wire [31:0] RS_ALU_rs2;
wire [5:0]  RS_ALU_op;
wire [`RoB_addr-1:0] RS_ALU_id;

//LSB & ROB
wire LSB_ROB_rob_valid;
wire [`RoB_addr-1:0] LSB_ROB_rob_head_id;

//ROB & RF
wire issue_valid;
wire [4:0] ROB_RF_index;
wire [`RoB_addr-1:0] ROB_RF_new_dep;
wire commit_valid;
wire [4:0] ROB_RF_regid;
wire [31:0] ROB_RF_value;
wire [`RoB_addr-1:0] ROB_RF_RoBindex;

MemoryController MemCtrl(
  .clk_in(clk_in),
  .rst_in(rst_in),
  .rdy_in(rdy_in),
  .mem_din(mem_din),
  .mem_dout(mem_dout),
  .mem_a(mem_a),
  .mem_wr(mem_wr),
  .ic_mem_ask(Mem_IC_ic_mem_ask),
  .ic_mem_addr(Mem_IC_ic_mem_addr),
  .ic_mem_valid(Mem_IC_ic_mem_valid),
  .ic_mem_inst(Mem_IC_ic_mem_inst),
  .lsb_request(Mem_LSB_lsb_request),
  .lsb_lors(Mem_LSB_lsb_lors),
  .lsb_mem_op(Mem_LSB_lsb_mem_op),
  .lsb_mem_addr(Mem_LSB_lsb_mem_addr),
  .lsb_mem_data(Mem_LSB_lsb_mem_data),
  .lsb_mem_valid(Mem_LSB_lsb_mem_valid),
  .lsb_mem_val(Mem_LSB_lsb_mem_val),
  .rob_clear(flush)
);

ICache IC(
  .clk_in(clk_in),
  .rst_in(rst_in),
  .rdy_in(rdy_in),
  .mem_valid(Mem_IC_ic_mem_valid),
  .mem_inst(Mem_IC_ic_mem_inst),
  .mem_ask(Mem_IC_ic_mem_ask),
  .mem_addr(Mem_IC_ic_mem_addr),
  .fetch_valid(IC_IF_fetch_valid),
  .fetch_pc(IC_IF_fetch_pc),
  .hit(IC_IF_hit),
  .hit_inst(IC_IF_hit_inst),
  .rob_clear(flush)
);

predictor Pre(
 .clk_in(clk_in),
 .rst_in(rst_in),
 .rdy_in(rdy_in),
 .if_pc(IF_Pre_pc_to_pre),
 .tojump(IF_Pre_jump),
 .rob_valid(Pre_ROB_rob_valid),
 .rob_now_pc(Pre_ROB_rob_now_pc),
 .should_jump(Pre_ROB_should_jump)
);

InsFetch IF(
.clk_in(clk_in),
.rst_in(rst_in),
.rdy_in(rdy_in),
.stall(DC_IF_stall),
.if_valid(DC_IF_if_valid),
.if_inst(DC_IF_if_inst),
.if_pc(DC_IF_if_pc),
.if_isjump(DC_IF_if_isjump),
.dc_valid(DC_IF_dc_valid),
.dc_nextpc(DC_IF_dc_nextpc),
.hit(IC_IF_hit),
.hit_inst(IC_IF_hit_inst),
.fetch_valid(IC_IF_fetch_valid),
.fetch_pc(IC_IF_fetch_pc),
.rob_clear(flush),
.rob_newpc(IF_ROB_rob_newpc),
.jump(IF_Pre_jump),
.pc_to_pre(IF_Pre_pc_to_pre)
);

Cdecoder Decoder(
  .clk_in(clk_in),
  .rst_in(rst_in),
  .rdy_in(rdy_in),
  .if_valid(DC_IF_if_valid),
  .instr(DC_IF_if_inst),
  .pc(DC_IF_if_pc),
  .isjump(DC_IF_if_isjump),
  .stall(DC_IF_stall), 
  .dc_valid(DC_IF_dc_valid),
  .dc_nextpc(DC_IF_dc_nextpc),
  .rf_rs1(DC_RF_rs1_id),
  .rf_rs2(DC_RF_rs2_id),
  .rf_val1(DC_RF_val1),
  .rf_val2(DC_RF_val2),
  .rf_has_rely1(DC_RF_has_rely1),
  .rf_has_rely2(DC_RF_has_rely2),
  .rf_rely1(DC_RF_get_rely1),
  .rf_rely2(DC_RF_get_rely2),
  .rob_id1(DC_ROB_rob_id1),
  .rob_id2(DC_ROB_rob_id2),
  .rob_id1_ready(DC_ROB_rob_id1_ready),
  .rob_id2_ready(DC_ROB_rob_id2_ready),
  .rob_id1_value(DC_ROB_rob_id1_value),
  .rob_id2_value(DC_ROB_rob_id2_value),
  .rob_clear(flush),
  .rob_full(DC_ROB_rob_full),
  .rob_index(DC_ROB_rob_index),
  .rob_inst_valid(DC_ROB_rob_inst_valid),
  .rob_inst_ready(DC_ROB_rob_inst_ready),
  .rob_inst_op(DC_ROB_inst_op),
  .rob_type(DC_ROB_rob_type),
  .rob_value(DC_ROB_rob_value),
  .rob_rd(DC_ROB_rob_rd),
  .rob_inst_pc(DC_ROB_rob_inst_pc),
  .rob_addr(DC_ROB_rob_addr),
  .rob_isjump(DC_ROB_rob_isjump),
  .rs_full(DC_RS_full),
  .rs_inst_valid(DC_RS_inst_valid),
  .lsb_full(DC_LSB_full),
  .lsb_inst_valid(DC_LSB_inst_valid),
  .inst_op(DC_inst_op),
  .RoB_index(DC_RoBindex),
  .inst_val1(DC_inst_val1),
  .inst_val2(DC_inst_val2),
  .inst_has_rely1(DC_inst_has_rely1),
  .inst_has_rely2(DC_inst_has_rely2),
  .inst_rely1(DC_inst_rely1),
  .inst_rely2(DC_inst_rely2),
  .inst_imm(DC_inst_imm)
);

ReorderBuffer ROB(
  .clk_in(clk_in),
  .rst_in(rst_in),
  .rdy_in(rdy_in),
  .inst_valid(DC_ROB_rob_inst_valid),
  .inst_ready(DC_ROB_rob_inst_ready),
  .inst_op(DC_ROB_inst_op),
  .inst_robtype(DC_ROB_rob_type),
  .inst_rd(DC_ROB_rob_rd),
  .inst_value(DC_ROB_rob_value),
  .inst_pc(DC_ROB_rob_inst_pc),
  .inst_addr(DC_ROB_rob_addr),
  .inst_isjump(DC_ROB_rob_isjump),
  .dc_rob_id1(DC_ROB_rob_id1),
  .dc_rob_id2(DC_ROB_rob_id2),
  .dc_rob_id1_ready(DC_ROB_rob_id1_ready),
  .dc_rob_id2_ready(DC_ROB_rob_id2_ready),
  .dc_rob_id1_value(DC_ROB_rob_id1_value),
  .dc_rob_id2_value(DC_ROB_rob_id2_value),
  .alu_valid(alu_valid),
  .alu_robid(alu_robid),
  .alu_val(alu_val),
  .lsb_valid(lsb_valid),
  .lsb_robid(lsb_robid),
  .lsb_val(lsb_val),
  .rf_issue(issue_valid),
  .rf_issue_rd(ROB_RF_index),
  .rf_new_dep(ROB_RF_new_dep),
  .rf_commit(commit_valid),
  .rf_commit_rd(ROB_RF_regid),
  .rf_robid(ROB_RF_RoBindex),
  .rf_value(ROB_RF_value),
  .rob_full(DC_ROB_rob_full),
  .rob_index(DC_ROB_rob_index),
  .lsb_rob_valid(LSB_ROB_rob_valid),
  .lsb_rob_headid(LSB_ROB_rob_head_id),
  .clear(flush),
  .new_pc(IF_ROB_rob_newpc),
  .rob_valid(Pre_ROB_rob_valid),
  .now_pc(Pre_ROB_rob_now_pc),
  .should_jump(Pre_ROB_should_jump)
);

LoadStoreBuffer LSB(
  .clk_in(clk_in),
  .rst_in(rst_in),
  .rdy_in(rdy_in),
  .lsb_clear(flush),
  .inst_valid(DC_LSB_inst_valid),
  .inst_op(DC_inst_op),
  .RoB_index(DC_RoBindex),
  .inst_val1(DC_inst_val1),
  .inst_val2(DC_inst_val2),
  .inst_has_rely1(DC_inst_has_rely1),
  .inst_has_rely2(DC_inst_has_rely2),
  .inst_rely1(DC_inst_rely1),
  .inst_rely2(DC_inst_rely2),
  .inst_imm(DC_inst_imm),
  .lsb_full(DC_LSB_full),
  .alu_valid(alu_valid),
  .alu_robid(alu_robid),
  .alu_val(alu_val),
  .mem_valid(Mem_LSB_lsb_mem_valid),
  .mem_val(Mem_LSB_lsb_mem_val),
  .request(Mem_LSB_lsb_request),
  .load_or_store(Mem_LSB_lsb_lors),
  .mem_op(Mem_LSB_lsb_mem_op),
  .mem_addr(Mem_LSB_lsb_mem_addr),
  .mem_data(Mem_LSB_lsb_mem_data),
  .rob_valid(LSB_ROB_rob_valid),
  .rob_head_id(LSB_ROB_rob_head_id),
  .lsb_valid(lsb_valid),
  .lsb_robid(lsb_robid),
  .lsb_val(lsb_val)
);

ReservationStation RS(
  .clk_in(clk_in),
  .rst_in(rst_in),
  .rdy_in(rdy_in),
  .rs_full(DC_RS_full),
  .inst_valid(DC_RS_inst_valid),
  .inst_op(DC_inst_op),
  .RoB_index(DC_RoBindex),
  .inst_val1(DC_inst_val1),
  .inst_val2(DC_inst_val2),
  .inst_has_rely1(DC_inst_has_rely1),
  .inst_has_rely2(DC_inst_has_rely2),
  .inst_rely1(DC_inst_rely1),
  .inst_rely2(DC_inst_rely2),
  .RS_clear(flush),
  .alu_rs1(RS_ALU_rs1),
  .alu_rs2(RS_ALU_rs2),
  .alu_op(RS_ALU_op),
  .alu_id(RS_ALU_id), 
  .alu_valid(alu_valid),
  .alu_robid(alu_robid),
  .alu_val(alu_val),
  .lsb_valid(lsb_valid),
  .lsb_robid(lsb_robid),
  .lsb_val(lsb_val)
);

ALU ALU(
  .clk_in(clk_in),
  .rst_in(rst_in),
  .rdy_in(rdy_in),
  .rs1(RS_ALU_rs1),
  .rs2(RS_ALU_rs2),
  .op(RS_ALU_op),
  .robid(RS_ALU_id),
  .result(alu_val),
  .alu_robid(alu_robid),
  .alu_valid(alu_valid),
  .rob_clear(flush)
);

RegisterFile RF(
  .clk_in(clk_in),
  .rst_in(rst_in),
  .rdy_in(rdy_in),
  .rs1_id(DC_RF_rs1_id),
  .rs2_id(DC_RF_rs2_id),
  .val1(DC_RF_val1),
  .val2(DC_RF_val2),
  .has_rely1(DC_RF_has_rely1),
  .has_rely2(DC_RF_has_rely2),
  .get_rely1(DC_RF_get_rely1),
  .get_rely2(DC_RF_get_rely2),
  .rf_clear(flush),
  .issue_valid(issue_valid),
  .index(ROB_RF_index),
  .new_dep(ROB_RF_new_dep),
  .commit_valid(commit_valid),
  .cdb_regid(ROB_RF_regid),
  .cdb_value(ROB_RF_value),
  .cdb_RoBindex(ROB_RF_RoBindex)
);

endmodule