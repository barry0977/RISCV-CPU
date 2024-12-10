`include "const.v"
module ReservationStation(
    input wire clk_in,
    input wire rst_in,
    input wire rdy_in,

    //执行完成后发送给RoB
    output wire [`RoB_addr-1:0] RS_RoBindex,
    output wire [31:0] RS_value,

    //接收CDB广播
    input wire [31:0] cdb_value,
    input wire [`RoB_addr-1:0] cdb_RoBindex,
);

reg                 busy[`RS_size-1:0];
reg [`RoB_addr-1:0] RoBindex[`RS_size-1:0];
reg [5:0]           op[`RS_size-1:0];
reg [31:0]          vj[`RS_size-1:0];
reg [31:0]          vk[`RS_size-1:0];
reg [`RoB_addr-1:0] qj[`RS_size-1:0];
reg [`RoB_addr-1:0] qk[`RS_size-1:0];
reg [31:0]          result[`RS_size-1:0];

always @(posedge clk_in)begin
end
endmodule