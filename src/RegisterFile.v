`include "const.v"

module RegisterFile(
    input wire clk_in,
    input wire rst_in,
    input wire rdy_in,

    //与RS/LSB交互
    input wire [4:0] rs1_id,
    input wire [4:0] rs2_id,
    output wire [31:0] vj,
    output wire [31:0] vk,
    output wire [`RoB_addr-1:0] qj,
    output wire [`RoB_addr-1:0] qk,

    //CDB广播更新
    input [4:0] cdb_regid,
    input [31:0] cdb_value,
    input [`RoB_addr-1:0] cdb_RoBindex
);

reg [31:0]          data[31:0];//储存的数据
reg [`RoB_addr-1:0] rely[31:0];//最新值将由哪条指令算出
reg                 busy[31:0];//是否有依赖

always @(posedge clk_in)begin
    if(rst_in)begin

    end
    else if(rdy_in)begin

    end
end

endmodule