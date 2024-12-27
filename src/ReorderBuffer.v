`include "const.v"

module ReorderBuffer(
    input wire clk_in,
    input wire rst_in,
    input wire rdy_in,

    //从Decoder获取的信息
    input wire inst_valid,//是否有指令传入
    input wire inst_ready,
    input wire inst_iscins,
    input wire [5:0] inst_op,
    input wire [2:0] inst_robtype,
    input wire [4:0] inst_rd,
    input wire [31:0] inst_value,
    input wire [31:0] inst_pc,
    input wire [31:0] inst_addr,
    input wire inst_isjump,

    //Decoder询问是否已经ready
    input wire [`RoB_addr-1:0] dc_rob_id1,
    input wire [`RoB_addr-1:0] dc_rob_id2,
    output wire dc_rob_id1_ready,
    output wire dc_rob_id2_ready,
    output wire [31:0] dc_rob_id1_value,
    output wire [31:0] dc_rob_id2_value,

    //ALU执行完成的结果
    input wire alu_valid,
    input wire [`RoB_addr-1:0] alu_robid,
    input wire [31:0] alu_val,

    //LSB执行完成的结果
    input wire lsb_valid,
    input wire [`RoB_addr-1:0] lsb_robid,
    input wire [31:0] lsb_val,

    //给RF更新(都用wire,没有延迟)
    //issue
    output wire rf_issue,
    output wire [4:0] rf_issue_rd,
    output wire [`RoB_addr-1:0] rf_new_dep,
    //commit
    output wire rf_commit,
    output wire [4:0] rf_commit_rd,
    output wire [`RoB_addr-1:0] rf_robid,
    output wire [31:0] rf_value,

    //是否已满
    output wire rob_full,
    output wire [`RoB_addr-1:0] rob_index,

    //向LSB提供头部id
    output wire lsb_rob_valid,
    output wire [`RoB_addr-1:0] lsb_rob_headid,

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
reg                 is_c[`RoB_size-1:0];
reg [2:0]           RoBtype[`RoB_size-1:0];
reg                 busy[`RoB_size-1:0];
reg [4:0]           dest[`RoB_size-1:0];//对应的目标寄存器
reg [31:0]          value[`RoB_size-1:0];//计算出来的值
reg [31:0]          addr[`RoB_size-1:0];//记录可能跳转的地址(用于branch指令)
reg [31:0]          pc[`RoB_size-1:0];//指令所在的位置
reg                 isjump[`RoB_size-1:0];//之前是否跳转
reg [`RoB_addr-1:0] head,tail;

wire empty,full;
wire ready_to_issue,ready_to_commit;

assign empty = head == tail;
assign full = (((tail + 1) % `RoB_size) == head);
assign rob_full = full;
assign rob_index = tail;
assign lsb_rob_valid = (!empty) && (RoBtype[head] == `load_ || RoBtype[head] == `store_);
assign lsb_rob_headid = head;

assign ready_to_issue = rdy_in && inst_valid && !full;
assign ready_to_commit = rdy_in && busy[head] && ready[head];
assign rf_commit = ready_to_commit && (RoBtype[head] == `toreg_ || RoBtype[head] == `load_ || RoBtype[head] == `else_);
assign rf_commit_rd = rf_commit ? dest[head] : 0;
assign rf_robid = rf_commit ? head : 0;
assign rf_value = rf_commit ? value[head] : 0;
assign rf_issue = ready_to_issue && (inst_robtype == `toreg_ || inst_robtype == `load_ || inst_robtype == `else_);
assign rf_issue_rd = rf_issue ? inst_rd : 0;
assign rf_new_dep = rf_issue ? tail : 0;

//Decoder询问是否ready
assign dc_rob_id1_ready = ready[dc_rob_id1] || (alu_valid && alu_robid == dc_rob_id1) || (lsb_valid && lsb_robid == dc_rob_id1);
assign dc_rob_id2_ready = ready[dc_rob_id2] || (alu_valid && alu_robid == dc_rob_id2) || (lsb_valid && lsb_robid == dc_rob_id2);
assign dc_rob_id1_value = ready[dc_rob_id1] ? value[dc_rob_id1] : (alu_valid && alu_robid == dc_rob_id1) ? alu_val : (lsb_valid && lsb_robid == dc_rob_id1) ? lsb_val : 0;
assign dc_rob_id2_value = ready[dc_rob_id2] ? value[dc_rob_id2] : (alu_valid && alu_robid == dc_rob_id2) ? alu_val : (lsb_valid && lsb_robid == dc_rob_id2) ? lsb_val : 0;

//debug info
wire [5:0] ophead= op[head];
wire [`RoB_addr-1:0] next_head;
assign next_head = head + 1;
wire [31:0] pc_head= pc[head];
wire [31:0] value_head = value[head];
wire [31:0] addr_head = addr[head];

integer i;
integer cnt;
always @(posedge clk_in) begin
    if(rst_in || (clear && rdy_in))begin
        //清除RoB
        if(rst_in)begin
            cnt = 0;
        end
        head <= 0;
        tail <= 0;
        clear <= 0;
        new_pc <= 0;
        for(i = 0; i < `RoB_size; i = i + 1)begin
            ready[i] <= 0;
            op[i] <= 0;
            is_c[i] <= 0;
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
            is_c[tail] <= inst_iscins;
            RoBtype[tail] <= inst_robtype;
            dest[tail] <= inst_rd;
            value[tail] <= inst_value;
            pc[tail] <= inst_pc;
            addr[tail] <= inst_addr;
            isjump[tail] <= inst_isjump;
        end

        //更新ready情况
        if(alu_valid)begin
            if(op[alu_robid] == `Jalr)begin
                addr[alu_robid] <= alu_val;
            end
            else begin
                value[alu_robid] <= alu_val;
            end
            ready[alu_robid] <= 1;
        end
        if(lsb_valid)begin
            ready[lsb_robid] <= 1;
            value[lsb_robid] <= lsb_val; 
        end

        //如果头部ready，则commit
        if(ready_to_commit)begin
            // $display("commit cnt: %h rob id: %h addr: %h value: %h",cnt,next_head,pc[head],value[head]);
            cnt = cnt + 1;
            head <= head + 1;
            busy[head] <= 0;
            ready[head] <= 0;
            case(RoBtype[head])
                //前三个都不需要操作，alu和lsb都已经操作了
                `toreg_:begin
                end
                `load_:begin
                end
                `store_:begin
                end
                `else_:begin
                    if(op[head] == `Jalr)begin
                        clear <= 1;
                        new_pc <= addr[head];
                    end
                end
                `branch_:begin
                    rob_valid <= 1;
                    now_pc <= pc[head];
                    //不需要跳转
                    if(value[head] == 0)begin
                        should_jump <= 0;
                        if(isjump[head])begin //预测需要跳转
                            clear <= 1;
                            if(is_c[head])begin
                                new_pc <= pc[head] + 2;
                            end
                            else begin
                                new_pc <= pc[head] + 4;
                            end
                        end
                        else begin //预测不需要跳转
                            clear <= 0;
                            new_pc <= 0;
                        end
                    end
                    //需要跳转
                    else begin
                        should_jump <= 1;
                        if(isjump[head])begin //预测需要跳转
                            clear <= 0;
                            new_pc <= 0;
                        end
                        else begin //预测不需要跳转
                            clear <= 1;
                            new_pc <= addr[head];
                        end
                    end
                end
                `exit_:begin
                end
            endcase
        end
        else begin
            clear <= 0;
            new_pc <= 0;
            rob_valid <= 0;
            now_pc <= 0;
            should_jump <= 0;
        end
    end
end
endmodule