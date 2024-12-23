`include "const.v"

module RegisterFile(
    input wire clk_in,
    input wire rst_in,
    input wire rdy_in,

    //与Decoder交互，获得寄存器的值或者依赖
    input wire [4:0] rs1_id,
    input wire [4:0] rs2_id,
    output wire [31:0] val1,
    output wire [31:0] val2,
    output wire has_rely1,
    output wire has_rely2,
    output wire [`RoB_addr-1:0] get_rely1,
    output wire [`RoB_addr-1:0] get_rely2,

    //是否需要清空
    input wire  rf_clear,

    //RoB issue时，更新依赖关系
    input wire issue_valid,
    input wire [4:0] index,
    input wire [`RoB_addr-1:0] new_dep,

    //ROB commit时，CDB广播更新
    input wire commit_valid,
    input wire [4:0] cdb_regid,
    input wire [31:0] cdb_value,
    input wire [`RoB_addr-1:0] cdb_RoBindex
);

reg [31:0]          data[31:0];//储存的数据
reg [`RoB_addr-1:0] rely[31:0];//最新值将由哪条指令算出
reg                 busy[31:0];//是否有依赖

assign has_rely1 = busy[rs1_id] || (issue_valid && (index != 0) && (index == rs1_id));
assign has_rely2 = busy[rs2_id] || (issue_valid && (index != 0) && (index == rs2_id)); 
assign val1 = data[rs1_id];
assign val2 = data[rs2_id];
assign get_rely1 = (issue_valid && (index != 0) && (index == rs1_id)) ? new_dep : rely[rs1_id];
assign get_rely2 = (issue_valid && (index != 0) && (index == rs2_id)) ? new_dep : rely[rs2_id];

//debug 
wire [31:0] x1_val = data[1];


integer i;
always @(posedge clk_in)begin
    if(rst_in)begin
        for(i = 0; i < 32; i = i + 1)begin 
            data[i] <= 0;
            rely[i] <= 0;
            busy[i] <= 0;
        end
    end
    else if(rdy_in)begin
        if(rf_clear)begin//分支预测错误，清空依赖关系
            for(i = 0; i < 32; i = i + 1)begin 
                rely[i] <= 0;
                busy[i] <= 0;
            end
        end 
        else begin
            if(issue_valid && index != 0)begin//添加依赖
                busy[index] <= 1;
                rely[index] <= new_dep;
            end
            if(commit_valid && cdb_regid != 0)begin//更新数据和依赖
                data[cdb_regid] <= cdb_value;
                if((rely[cdb_regid] == cdb_RoBindex)&&(index != cdb_regid))begin
                    busy[cdb_regid] <= 0;
                    rely[cdb_regid] <= 0;
                end
            end
        end
    end
end

endmodule