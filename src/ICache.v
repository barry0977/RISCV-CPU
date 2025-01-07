`include "const.v"

module ICache(
    input wire clk_in,
    input wire rst_in,
    input wire rdy_in,

    //与MemCtrl交互
    input wire mem_valid,
    input wire [31:0] mem_inst,
    output reg mem_ask,
    output reg [31:0] mem_addr,

    //与InsFetch交互
    input wire fetch_valid,
    input wire [31:0] fetch_pc,
    output reg hit,
    output reg [31:0] hit_inst,

    input  wire rob_clear
);

//地址有效位为[17:0]
//[1:0]无意义，[`Cache_addr:1]作为index,其余位作为tag
reg                    valid[`Cache_size-1:0];
reg [31:0]             data[`Cache_size-1:0];
reg [17:`Cache_addr+1] tag[`Cache_size-1:0];

reg state;//记录当前是否在从memory取指令
wire exist;//是否存在cache中
wire [`Cache_addr:1] index = fetch_pc[`Cache_addr:1];
wire [`Cache_addr:1] mem_index = mem_addr[`Cache_addr:1];
assign exist = valid[index] && tag[index] == fetch_pc[17:`Cache_addr+1];

integer i;
always @(posedge clk_in)begin
    if(rst_in)begin
        for(i = 0; i < `Cache_size; i = i + 1)begin
            valid[i] <= 0;
            data[i] <= 0;
            tag[i] <= 0;
        end
    end
    else if(rdy_in)begin
        if(fetch_valid)begin
            if(state == 1)begin //在从内存取指令
                if(mem_valid)begin
                    state <= 0;
                    mem_ask <= 0;
                    mem_addr <= 0;
                    valid[mem_index] <= 1;
                    data[mem_index] <= mem_inst;
                    tag[mem_index] <= mem_addr[17:`Cache_addr+1];
                end
            end
            else begin 
                if(exist)begin //命中
                    hit <= 1;
                    hit_inst <= data[fetch_pc[`Cache_addr:1]];
                end
                else begin
                    state <= 1;
                    mem_ask <= 1;
                    mem_addr <= fetch_pc;
                end
            end
        end
        else begin
            hit <= 0;
            hit_inst <= 0;
        end
    end
end
endmodule