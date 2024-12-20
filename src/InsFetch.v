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
wire [31:0] instr;
wire [31:0] imm_B,imm_J;
wire is_jal,is_jalr,is_B;

assign instr = hit_inst;
assign imm_B = {{20{instr[31]}},instr[7],instr[30:25],instr[11:8],1'b0};
assign imm_J = {{12{instr[31]}},instr[19:12],instr[20],instr[30:21],1'b0};
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
    else if(rdy_in)begin
        //分支预测错误，修改pc
        if(rob_clear)begin
            PC <= rob_newpc;
            fetch_valid <= 0;
            fetch_pc <= 0;
            if_valid <= 0;
            if_inst <= 0;
            if_pc <= 0;
            state <= 0;//恢复正常读取指令
        end
        if(state == 0)begin 
            if(work == 0)begin //空闲,则向ICache请求指令
                if(!stall)begin
                    fetch_valid <= 1;
                    fetch_pc <= PC;
                    work <= 1;//进入工作状态
                end
                else begin
                    fetch_valid <= 0;
                    fetch_pc <= 0;
                end
                if_valid <= 0;
                if_inst <= 0;
                if_pc <= 0;
                if_isjump <= 0;
            end
            else begin //busy(icache还没返回指令)
                if(!stall && hit)begin //获得ICache指令，发送给Decoder
                    if_valid <= 1;
                    if_inst <= hit_inst;
                    if_pc <= PC;
                    if(is_jal)begin //读到Jal，直接跳转pc
                        PC <= PC + imm_J;
                        if_isjump <= 1;
                    end
                    else if(is_jalr)begin //读到Jalr，暂停直到获得结果,state=1
                        state <= 1;
                        if_isjump <= 0;
                    end
                    else if(is_B)begin
                        if(jump)begin //预测跳转
                            PC <= PC + imm_B;
                            if_isjump <= 1;
                        end
                        else begin //预测不跳转
                            PC <= PC + 4;
                            if_isjump <= 0;
                        end
                    end
                    else begin
                        PC <= PC + 4;
                        if_isjump <= 0;
                    end
                    fetch_valid <= 0;
                    fetch_pc <= 0;
                    work <= 0;
                end
            end
        end
    end
end
endmodule