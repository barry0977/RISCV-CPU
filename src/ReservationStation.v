`include "const.v"
module ReservationStation(
    input wire clk_in,
    input wire rst_in,
    input wire rdy_in,

    //是否已满
    output wire full,

    //Decoder发射
    input wire  inst_valid,
    input wire [5:0] inst_op,
    input wire [`RoB_addr-1:0] RoB_index,
    input wire [31:0] inst_val1,
    input wire [31:0] inst_val2,
    input wire inst_has_rely1,
    input wire inst_has_rely2,
    input wire [`RoB_addr-1:0] rely1,
    input wire [`RoB_addr-1:0] rely2,

    //是否清空RS
    input wire RS_clear,

    //发送给ALU执行
    output reg [31:0] alu_rs1,
    output reg [31:0] alu_rs2,
    output reg [5:0]  alu_op,

    //执行完成后发送给RoB
    output wire [`RoB_addr-1:0] RS_RoBindex,
    output wire [31:0] RS_value,

    //接收CDB广播
    input wire [31:0] cdb_value,
    input wire [`RoB_addr-1:0] cdb_RoBindex
);

reg                 busy[`RS_size:0];
reg [`RoB_addr-1:0] RoBindex[`RS_size-1:0];
reg [5:0]           op[`RS_size-1:0];
reg [31:0]          vj[`RS_size-1:0];
reg [31:0]          vk[`RS_size-1:0];
reg                 is_qj[`RS_size:0];
reg                 is_qk[`RS_size-1:0];
reg [`RoB_addr-1:0] qj[`RS_size-1:0];
reg [`RoB_addr-1:0] qk[`RS_size-1:0];
reg [31:0]          result[`RS_size-1:0];

wire ready[`RS_size-1:0];
wire [`RS_addr:0] first_empty;
wire [`RS_addr:0] first_exe;

//是否可以执行
generate
    genvar i;
    for(i = 0; i < `RS_size; i = i + 1)begin
        assign ready[i] = busy[i] && ((!is_qj[i]) && (!is_qk[i]));
    end
endgenerate

//找到第一行空的和第一行可以执行的
assign first_empty = busy[0] == 0 ? 0 : busy[1] == 0 ? 1 : busy[2] == 0 ? 2 : busy[3] == 0 ? 3 : busy[4] == 0 ? 4 : busy[5] == 0 ? 5 : busy[6] == 0 ? 6 : busy[7] == 0 ? 7 : 8;
assign first_exe = ready[0] == 0 ? 0 : ready[1] == 0 ? 1 : ready[2] == 0 ? 2 : ready[3] == 0 ? 3 : ready[4] == 0 ? 4 : ready[5] == 0 ? 5 : ready[6] == 0 ? 6 : ready[7] == 0 ? 7 : 8;

assign full = first_empty == 8;

always @(posedge clk_in)begin
    integer i;
    if(rst_in||RS_clear) begin
        for(i = 0; i < `RS_size; i = i + 1)begin
            busy[i] <= 0;
            RoBindex[i] <= 0;
            op[i] <= 0;
            vj[i] <= 0;
            vk[i] <= 0;
            qj[i] <= 0;
            qk[i] <= 0;
            result[i] <= 0;
        end
    end
    else if(rdy_in)begin
        //加入RS
        if(inst_valid && (first_empty != 8))begin
            busy[first_empty] <= 1;
            RoBindex[first_empty] <= RoB_index;
            op[first_empty] <= inst_op;
            vj[first_empty] <= inst_val1;
            vk[first_empty] <= inst_val2;
            is_qj[first_empty] <= inst_has_rely1;
            is_qk[first_empty] <= inst_has_rely2;
            qj[first_empty] <= rely1;
            qk[first_empty] <= rely2;
        end
        //可以执行，交给ALU
        if(first_exe != 8)begin
            alu_rs1 <= vj[first_exe];
            alu_rs2 <= vk[first_exe];
            alu_op <= op[first_exe];
        end else begin
            alu_rs1 <= 0;
            alu_rs2 <= 0;
            alu_op <= 0;
        end
        //更新依赖
        for(i = 0; i < `RS_size; i = i + 1)begin
            if(busy[i])begin
                if(is_qj[i] && (qj[i] == cdb_RoBindex))begin
                    is_qj[i] <= 0;
                    vj[i] <= cdb_value;
                end
                if(is_qk[i] && (qk[i] == cdb_RoBindex))begin
                    is_qk[i] <= 0;
                    vk[i] <= cdb_value; 
                end
            end
        end
    end
end
endmodule