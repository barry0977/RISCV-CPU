·include "const.v"
`define toreg_ 3'b0
`define load_ 3'b1
`define store_ 3'b2
`define branch_ 3'b3
`define else_ 3'b4 //Lui,Auipc,Jal,Jalr
`define exit_ 3'b5

module ReorderBuffer(
    input wire clk_in,
    input wire rst_in,
    input wire rdy_in,

    //从Decoder获取的信息
    input wire inst_valid,//是否有指令传入
    input wire inst_ready,
    input wire [5:0] inst_op,
    input wire [4:0] inst_rd,
    input wire [31:0] inst_value,
    input wire [31:0] inst_pc,
    input wire inst_isjump,

    //ALU执行完成的结果
    input wire alu_valid,
    input wire [`RoB_addr-1:0] alu_robid,
    input wire [31:0] alu_val,

    //LSB执行完成的结果
    input wire lsb_valid,
    input wire [`RoB_addr-1:0] lsb_robid,
    input wire [31:0] lsb_val,

    //给RF更新
    //issue
    output reg rf_issue,
    output reg [4:0] rf_issue_rd,
    output reg [`RoB_addr-1:0] rf_new_dep,
    //commit
    output reg rf_commit,
    output reg [4:0] rf_commit_rd,
    output reg [`RoB_addr-1:0] rf_robid,
    output reg [31:0] rf_value,

    //是否已满
    output wire rob_full,

    //分支预测错误，发出clear信号
    output reg clear,
    output reg [31:0] new_pc,//告诉IF新的PC值

    //与Predictor交互
    output reg rob_valid,
    output reg [31:0] now_pc,
    output reg should_jump
);

reg                 ready[`RoB_size-1:0];
reg [5:0]           op[`RoB_size-1:0];
reg [2:0]           RoBtype[`RoB_size-1:0];
reg                 busy[`RoB_size-1:0];
reg [4:0]           dest[`RoB_size-1:0];//对应的目标寄存器
reg [31:0]          value[`RoB_size-1:0];//计算出来的值
reg [31:0]          addr[`RoB_size-1:0];//记录可能跳转的地址(用于branch指令)
reg [31:0]          pc[`RoB_size-1:0];//指令所在的位置
reg                 isjump[`RoB_size-1:0];//之前是否跳转
reg [`RoB_addr-1:0] head,tail;

wire empty,full;
wire [2:0] robtype;//rob类型

assign robtype = op <= `Jalr ? `else_ : op <= `Bgeu : `branch_ : op <= `Lhu ? load_ : op <= `Sw ? `store_ : op <= `And ? `toreg_ : `exit_; 

assign empty = head == tail;
assign full = tail + 1 == headl
assign rob_full = full;

always @(posedge clk_in) begin
    if(rst_in||clear)begin
        //清除RoB
        head <= 0;
        tail <= 0;
        clear <= 0;
        new_pc <= 0;
        for(int i = 0; i < `RoB_size; i = i + 1)begin
            ready[i] <= 0;
            op[i] <= 0;
            RoBtype[i] <= 0;
            busy[i] <= 0;
            value[i] <= 0;
            dest[i] <= 0;
            addr[i] <= 0;
            pc[i] <= 0;
            isjump[i] <= 0;
        end
    end
    else if(rdy_in)begin
        //issue,加入RoB末尾
        if(inst_valid && !full)begin
            tail <= tail + 1;
            busy[tail] <= 1;
            ready[tail] <= inst_ready;
            op[tail] <= inst_op;
            RoBtype[tail] <= robtype;
            dest[tail] <= inst_rd;
            value[tail] <= inst_value;
            pc[i] <= inst_pc;
            isjump[i] <= inst_isjump;
            rf_issue <= 1;
            rf_issue_rd <= inst_rd;
            rf_new_dep <= tail;
        end
        else begin
            rf_issue <= 0;
            rf_issue_rd <= 0;
            rf_new_dep <= 0;
        end

        //更新ready情况
        if(alu_valid)begin
            ready[alu_robid] <= 1;
            value[alu_robid] <= alu_val;
        end
        if(lsb_valid)begin
            ready[lsb_robid] <= 1;
            value[lsb_robid] <= lsb_val; 
        end

        //如果头部ready，则commit
        if(busy[head]&&ready[head])begin
            head <= head + 1;
            busy[head] <= 0;
            ready[head] <= 0;
            rf_commit <= 1;
            rf_commit_rd <= dest[head];
            rf_robid <= head;
            rf_value <= value[head];
            case(RoBtype[head])
                `toreg_:begin
                end
                `load_:begin
                end
                `store_:begin
                end
                `else_:begin
                end
                `branch_:begin
                    rob_valid <= 1;
                    now_pc <= pc[head];
                    //不需要跳转
                    if(value[head] == 0)begin
                        should_jump <= 0;
                        if(isjump[head])begin //预测需要跳转
                            clear <= 1;
                            new_pc <= pc[head] + 4;
                        end
                        else begin //预测不需要跳转
                        end
                    end
                    //需要跳转
                    else begin
                        should_jump <= 1;
                        if(isjump[head])begin //预测需要跳转
                        end
                        else begin //预测不需要跳转
                            clear <= 1;
                            new_pc <= addr[head];
                        end
                    end
                end
            endcase
        end
        else begin
            rf_commit <= 0;
            rf_commit_rd <= 0;
            rf_robid <= 0;
            rf_value <= 0;
            clear <= 0;
            new_pc <= 0;
            rob_valid <= 0;
            now_pc <= 0;
            should_jump <= 0;
        end
    end
end
endmodule