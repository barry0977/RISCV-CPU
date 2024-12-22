`include "const.v"
module ReservationStation(
    input wire clk_in,
    input wire rst_in,
    input wire rdy_in,

    //是否已满
    output wire rs_full,

    //Decoder发射
    input wire inst_valid,
    input wire [5:0] inst_op,
    input wire [`RoB_addr-1:0] RoB_index,
    input wire [31:0] inst_val1,
    input wire [31:0] inst_val2,
    input wire inst_has_rely1,
    input wire inst_has_rely2,
    input wire [`RoB_addr-1:0] inst_rely1,
    input wire [`RoB_addr-1:0] inst_rely2,

    //是否清空RS
    input wire RS_clear,

    //发送给ALU运算
    output reg [31:0] alu_rs1,
    output reg [31:0] alu_rs2,
    output reg [5:0]  alu_op,
    output reg [`RoB_addr-1:0] alu_id, 
    //ALU结果更新
    input wire alu_valid,
    input wire [`RoB_addr-1:0] alu_robid,
    input wire [31:0] alu_val,

    //LSB结果更新
    input wire lsb_valid,
    input wire [`RoB_addr-1:0] lsb_robid,
    input wire [31:0] lsb_val
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
wire new_has_rely1,new_has_rely2;
wire [31:0] new_val1,new_val2;

//是否可以执行
generate
    genvar j;
    for(j = 0; j < `RS_size; j = j + 1)begin:block
        assign ready[j] = busy[j] && ((!is_qj[j]) && (!is_qk[j]));
    end
endgenerate

//找到第一行空的和第一行可以执行的
assign first_empty = busy[0] == 0 ? 0 : busy[1] == 0 ? 1 : busy[2] == 0 ? 2 : busy[3] == 0 ? 3 : busy[4] == 0 ? 4 : busy[5] == 0 ? 5 : busy[6] == 0 ? 6 : busy[7] == 0 ? 7 : 8;
assign first_exe = ready[0] == 0 ? 0 : ready[1] == 0 ? 1 : ready[2] == 0 ? 2 : ready[3] == 0 ? 3 : ready[4] == 0 ? 4 : ready[5] == 0 ? 5 : ready[6] == 0 ? 6 : ready[7] == 0 ? 7 : 8;

assign rs_full = first_empty == 8;

//判断同一周期新更新是否会更新依赖
assign new_has_rely1 = inst_has_rely1 && !(alu_valid && (alu_robid == inst_rely1)) && !(lsb_valid && (lsb_robid == inst_rely1));
assign new_has_rely2 = inst_has_rely2 && !(alu_valid && (alu_robid == inst_rely2)) && !(lsb_valid && (lsb_robid == inst_rely2));
assign new_val1 = !inst_has_rely1 ? inst_val1 : (alu_valid && (alu_robid == inst_rely1)) ? alu_val : (lsb_valid && (lsb_robid == inst_rely1)) ? lsb_val : 0;
assign new_val2 = !inst_has_rely2 ? inst_val2 : (alu_valid && (alu_robid == inst_rely2)) ? alu_val : (lsb_valid && (lsb_robid == inst_rely2)) ? lsb_val : 0;

integer i;
always @(posedge clk_in)begin
    if(rst_in || RS_clear) begin
        alu_op <= 0;
        alu_rs1 <= 0;
        alu_rs2 <= 0;
        alu_id <= 0;
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
        if(inst_valid && (first_empty < `RS_size))begin
            busy[first_empty] <= 1;
            RoBindex[first_empty] <= RoB_index;
            op[first_empty] <= inst_op;
            vj[first_empty] <= new_val1;
            vk[first_empty] <= new_val2;
            is_qj[first_empty] <= new_has_rely1;
            is_qk[first_empty] <= new_has_rely2;
            qj[first_empty] <= inst_rely1;
            qk[first_empty] <= inst_rely2;
        end
        //可以执行，交给ALU
        if(first_exe < `RS_size)begin
            alu_rs1 <= vj[first_exe];
            alu_rs2 <= vk[first_exe];
            alu_op <= op[first_exe];
            alu_id <= RoBindex[first_exe];
            busy[first_exe] <= 0;
        end else begin
            alu_rs1 <= 0;
            alu_rs2 <= 0;
            alu_op <= 0;
            alu_id <= 0;
        end
        //更新依赖
        for(i = 0; i < `LSB_size; i = i + 1)begin
            if(busy[i])begin
                if(alu_valid)begin
                    if(is_qj[i] && (alu_robid == qj[i]))begin
                        is_qj[i] <= 0;
                        vj[i] <= alu_val;
                    end
                    if(is_qk[i] && (alu_robid == qk[i]))begin
                        is_qk[i] <= 0;
                        vk[i] <= alu_val;
                    end
                end
                if(lsb_valid)begin
                    if(is_qj[i] && (lsb_robid == qj[i]))begin
                        is_qj[i] <= 0;
                        vj[i] <= lsb_val;
                    end
                    if(is_qk[i] && (lsb_robid == qk[i]))begin
                        is_qk[i] <= 0;
                        vk[i] <= lsb_val;
                    end
                end
            end
        end
    end
end
endmodule