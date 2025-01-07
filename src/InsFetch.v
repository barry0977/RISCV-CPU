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


reg [31:0] PC;
reg state;//0-idle,1-stall(jalr)
reg work;//0-idle,1-busy

assign pc_to_pre = PC;//直接用导线连接，可以在同一个周期内获得预测结果
wire is_cins = hit_inst[1:0] != 2'b11;

wire is_jal = hit_inst[6:0] == `Jal_ins;
wire is_jalr = hit_inst[6:0] == `Jalr_ins;
wire is_B = hit_inst[6:0] == `B_ins;
wire is_jal_c = (hit_inst[1:0] == 2'b01) && (hit_inst[15:13] == 3'b001 || hit_inst[15:13] == 3'b101);//c.jal,c.j
wire is_jalr_c = (hit_inst[1:0] == 2'b10) && (hit_inst[15:13] == 3'b100) && (hit_inst[6:2] == 0);//c.jr,c.jalr
wire is_B_c = (hit_inst[1:0] == 2'b01) && (hit_inst[15:13] == 3'b110 || hit_inst[15:13] == 3'b111);//c.beqz,c.bnez
wire jal = (is_cins && is_jal_c) || (!is_cins && is_jal);
wire jalr = (is_cins && is_jalr_c) || (!is_cins && is_jalr);
wire B = (is_cins && is_B_c) || (!is_cins && is_B);

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
                    if(jal)begin //读到Jal，直接跳转pc
                        if_isjump <= 1;
                    end
                    else if(jalr)begin //读到Jalr，暂停直到获得结果,state=1
                        if_isjump <= 0;
                    end
                    else if(B)begin
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
                    if(jalr)begin
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