`include "const.v"

module LoadStoreBuffer(
    input wire clk_in,
    input wire rst_in,
    input wire rdy_in


);

reg [5:0]           op[`LSB_size-1:0];
reg [`RoB_addr-1:0] RoBindex[`LSB_size-1:0];
reg [31:0]          vj[`LSB_size-1:0];
reg [31:0]          vk[`LSB_size-1:0];
reg [`RoB_addr-1:0] qj[`LSB_size-1:0];
reg [`RoB_addr-1:0] qk[`LSB_size-1:0];
reg [31:0]          imm[`LSB_size-1:0];

always @(posedge clk_in)begin
    if(rst_in)begin
    end
    else if(rdy_in)begin
    end
end
endmodule