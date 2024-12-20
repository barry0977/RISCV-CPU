`include "const.v"
module predictor(
    input wire clk_in,
    input wire rst_in,
    input wire rdy_in,

    //与InsFetch交互
    input wire [31:0] if_pc,
    output wire tojump,

    //与RoB交互
    input wire rob_valid,
    input wire [31:0] rob_now_pc,
    input wire should_jump
);

//hash [7:2]
reg [1:0] pred[63:0]; // 00,01-不跳转，10,11-跳转
wire [5:0] index;
wire [5:0] if_index;

assign index = rob_now_pc[7:2];
assign if_index = if_pc[7:2];
assign tojump = pred[if_index] >= 2'b10;

integer i;
always @(posedge clk_in)begin
    if(rst_in)begin
        for(i = 0; i < 64; i = i + 1)begin
            pred[i] <= 2'b01;
        end
    end
    else if(rdy_in)begin
        //根据RoB最终结果更新分支预测器
        if(rob_valid)begin
            if(should_jump)begin
                pred[index] <= pred[index] < 3 ? pred[index] + 1 : pred[index];
            end
            else begin
                pred[index] <= pred[index] > 0 ? pred[index] - 1 : pred[index];
            end
        end
    end
end
endmodule
