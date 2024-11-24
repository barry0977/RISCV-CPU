·include "const.v"

module ReorderBuffer(
    input wire clk_in,
    input wire rst_in,
    input wire rdy_in,

    //RS执行完成的结果
    input wire [`RoB_addr-1:0] RS_RoBindex,
    input wire [31:0] RS_value,

    //LSB执行完成的结果
    input wire [`RoB_addr-1:0] LSB_RoBindex,
    input wire [31:0] LSB_value,

    //提交时
    
    //是否已满
    output wire RoB_full
);

reg [`RoB_addr-1:0]  index[`RoB_size=1:0];
reg                 ready[`RoB_size-1:0];
reg [4:0]           dest[`RoB_size-1:0];//对应的目标寄存器
reg [31:0]          value[`RoB_size-1:0];//计算出来的值
reg [`RoB_addr-1:0] head,tail;

always @(posedge clk_in) begin
    if(rst_in)begin
        //清除RoB
    end
    else if(rdy_in)begin
    end
end
endmodule