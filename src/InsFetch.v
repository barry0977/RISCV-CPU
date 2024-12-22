`include "const.v"
module InsFetch(
    input wire clk_in,
    input wire rst_in,
    input wire rdy_in,

    //RoB/RS/LSB已满，不能再发射
    input wire stall,

    //发送给Decoder
    output reg if_valid,
    output reg [31:0] if_inst,
    output reg [31:0] if_pc,
    output reg if_isjump,
    input  wire dc_valid,
    input  wire [31:0] dc_nextpc,

    //与ICache交互
    input wire hit,
    input wire [31:0] hit_inst,
    output reg fetch_valid,
    output reg [31:0] fetch_pc,

    //RoB发送信号，修改pc
    input wire rob_clear,
    input wire [31:0] rob_newpc,

    //与Predictor交互，是否跳转
    input wire jump,//1-jump,0-not jump
    output wire [31:0] pc_to_pre
);

assign pc_to_pre = PC;//直接用导线连接，可以在同一个周期内获得预测结果

reg [31:0] PC;
reg state;//0-idle,1-stall(jalr)
reg work;//0-idle,1-busy
wire is_jal,is_jalr,is_B;

assign is_jal = hit_inst[6:0] == `Jal_ins;
assign is_jalr = hit_inst[6:0] == `Jalr_ins;
assign is_B = hit_inst[6:0] == `B_ins;

always @(posedge clk_in)begin
    if(rst_in)begin
        if_valid <= 0;
        if_inst <= 0;
        if_pc <= 0;
        fetch_valid <= 0;
        fetch_pc <= 0;
        PC <= 0;
        state <= 0;
        work <= 0;
    end
    //分支预测错误，修改pc
    else if(rob_clear)begin
        PC <= rob_newpc;
        fetch_valid <= 0;
        fetch_pc <= 0;
        if_valid <= 0;
        if_inst <= 0;
        if_pc <= 0;
        state <= 0;//恢复正常读取指令
        work <= 0;
    end
    else if(rdy_in)begin
        if(state == 0)begin 
            if(work == 0)begin //空闲,则向ICache请求指令
                if(!stall)begin 
                    fetch_valid <= 1;
                    fetch_pc <= PC;
                    work <= 1;//进入工作状态
                end
                else begin //暂停,直到Jalr返回结果
                    fetch_valid <= 0;
                    fetch_pc <= 0;
                end
            end
            else begin //busy(icache还没返回指令)
                if(!stall && hit)begin //获得ICache指令，发送给Decoder
                    if_valid <= 1;
                    if_inst <= hit_inst;
                    if_pc <= PC;
                    if(is_jal)begin //读到Jal，直接跳转pc
                        if_isjump <= 1;
                    end
                    else if(is_jalr)begin //读到Jalr，暂停直到获得结果,state=1
                        // state <= 1;
                        if_isjump <= 0;
                    end
                    else if(is_B)begin
                        if(jump)begin //预测跳转
                            if_isjump <= 1;
                        end
                        else begin //预测不跳转
                            if_isjump <= 0;
                        end
                    end
                    else begin
                        if_isjump <= 0;
                    end
                    fetch_valid <= 0;
                    fetch_pc <= 0;
                end

                if(dc_valid)begin //Decoder获取了指令
                    if(is_jalr)begin
                        state <= 1;
                    end
                    PC <= dc_nextpc;
                    work <= 0;
                    if_valid <= 0;
                    if_inst <= 0;
                    if_pc <= 0;
                    if_isjump <= 0;
                end
            end
        end
    end
end
endmodule