`include "const.v"

module LoadStoreBuffer(
    input wire clk_in,
    input wire rst_in,
    input wire rdy_in,

    input wire lsb_clear,

    //Decoder发送给LSB
    input wire inst_valid,
    input wire [5:0] inst_op,
    input wire [`RoB_addr-1:0] RoB_index,
    input wire [31:0] inst_val1,
    input wire [31:0] inst_val2,
    input wire inst_has_rely1,
    input wire inst_has_rely2,
    input wire [`RoB_addr-1:0] inst_rely1,
    input wire [`RoB_addr-1:0] inst_rely2,
    input wire [31:0] inst_imm,

    output wire lsb_full,

    //ALU结果更新
    input wire alu_valid,//有新结果更新
    input wire [`RoB_addr-1:0] alu_robid,
    input wire [31:0] alu_val,

    //与MemControl交互
    input wire mem_valid,
    input wire [31:0] mem_val,
    output reg request,//发送load或store请求
    output reg load_or_store,//0-load,1-store
    output reg [5:0] mem_op,
    output reg [31:0] mem_addr,
    output reg [31:0] mem_data,

    //与ROB交互
    input wire rob_valid,
    input wire [`RoB_addr-1:0] rob_head_id,//rob头部的id，只有在id与lsb头部id相同时可以执行
    
    //若load,则广播给所有元件
    output reg lsb_valid,
    output reg [`RoB_addr-1:0] lsb_robid,
    output reg [31:0] lsb_val

);

reg                 busy[`LSB_size-1:0];
reg                 ready[`LSB_size-1:0];
reg                 result[`LSB_size-1:0];
reg [5:0]           op[`LSB_size-1:0];
reg [`RoB_addr-1:0] RoBindex[`LSB_size-1:0];
reg [31:0]          vj[`LSB_size-1:0];
reg [31:0]          vk[`LSB_size-1:0];
reg                 is_qj[`LSB_size-1:0];
reg                 is_qk[`LSB_size-1:0];
reg [`RoB_addr-1:0] qj[`LSB_size-1:0];
reg [`RoB_addr-1:0] qk[`LSB_size-1:0];
reg [31:0]          imm[`LSB_size-1:0];
reg [31:0]          addr[`LSB_size-1:0];
reg [`LSB_addr-1:0] head,tail;

wire full,empty;
wire new_has_rely1,new_has_rely2;
wire [31:0] new_val1,new_val2;

reg [1:0] state;//0-空闲,1-load,2-store

assign empty = head == tail;
assign full = (((tail + 1) % `LSB_size) == head);
assign lsb_full = full;

//判断同一周期新更新是否会更新依赖
assign new_has_rely1 = inst_has_rely1 && !(alu_valid && (alu_robid == inst_rely1)) && !(lsb_valid && (lsb_robid == inst_rely1));
assign new_has_rely2 = inst_has_rely2 && !(alu_valid && (alu_robid == inst_rely2)) && !(lsb_valid && (lsb_robid == inst_rely2));
assign new_val1 = !inst_has_rely1 ? inst_val1 : (alu_valid && (alu_robid == inst_rely1)) ? alu_val : (lsb_valid && (lsb_robid == inst_rely1)) ? lsb_val : 0;
assign new_val2 = !inst_has_rely2 ? inst_val2 : (alu_valid && (alu_robid == inst_rely2)) ? alu_val : (lsb_valid && (lsb_robid == inst_rely2)) ? lsb_val : 0;

//debug
wire [`RoB_addr-1:0] head_robid = RoBindex[head];
wire [31:0] vj_head = vj[head];
wire [31:0] vk_head = vk[head];

integer i;
always @(posedge clk_in)begin
    if(rst_in||lsb_clear)begin
        state <= 0;
        head <= 0;
        tail <= 0;
        request <= 0;
        load_or_store <= 0;
        mem_op <= 0;
        mem_addr <= 0;
        mem_data <= 0;
        lsb_valid <= 0;
        lsb_robid <= 0;
        lsb_val <= 0;
        for(i = 0; i < `LSB_size; i = i + 1)begin
            busy[i] <= 0;
            ready[i] <= 0;
            result[i] <= 0;
            op[i] <= 0;
            RoBindex[i] <= 0;
            vj[i] <= 0;
            vk[i] <= 0;
            is_qj[i] <= 0;
            is_qk[i] <= 0;
            qj[i] <= 0;
            qk[i] <= 0;
            imm[i] <= 0;
            addr[i] <= 0;
        end
    end
    else if(rdy_in)begin
        //新加入LSB
        if(inst_valid && full == 0)begin
            tail <= tail + 1;
            busy[tail] <= 1;
            op[tail] <= inst_op;
            RoBindex[tail] <= RoB_index;
            vj[tail] <= new_val1;
            vk[tail] <= new_val2;
            is_qj[tail] <= new_has_rely1;
            is_qk[tail] <= new_has_rely2;
            qj[tail] <= inst_rely1;
            qk[tail] <= inst_rely2;
            imm[tail] <= inst_imm;
            if((new_has_rely1)||(new_has_rely2))begin
                ready[tail] <= 0;
            end
            else begin
                ready[tail] <= 1;
            end
        end
        //判断是否能够执行
        case(state)
        0:begin
            lsb_valid <= 0;
            if(!empty && is_qj[head] == 0 && is_qk[head] == 0)begin
                if(op[head] >= `Lb && op[head] <= `Lhu)begin //load可以直接执行
                    head <= head + 1;
                    request <= 1;
                    load_or_store <= 0;
                    mem_op <= op[head];
                    mem_addr <= vj[head] + vk[head];
                    mem_data <= 0;
                    lsb_robid <= RoBindex[head];
                    state <= 1;
                end
                else if(rob_valid && rob_head_id == RoBindex[head])begin //store要等到rob头部也是该指令才执行
                    head <= head + 1;
                    request <= 1;
                    load_or_store <= 1;
                    mem_op <= op[head];
                    mem_addr <= vj[head] + imm[head];
                    mem_data <= vk[head];
                    lsb_robid <= RoBindex[head];
                    state <= 2;
                end
            end
        end
        1:begin //load
            if(mem_valid)begin
                lsb_valid <= 1;
                lsb_val <= mem_val;
                state <= 0;
                request <= 0;
            end
            else begin
                lsb_valid <= 0;
            end
        end
        2:begin //store
            if(mem_valid)begin
                lsb_valid <= 1;
                lsb_val <= mem_addr;
                state <= 0;
                request <= 0;
            end
            else begin
                lsb_valid <= 0;
            end
        end
        endcase
        //更新依赖
        for(i = 0; i < `LSB_size; i = i + 1)begin
            if(busy[i])begin
                if(alu_valid)begin
                    if(is_qj[i] && (alu_robid == qj[i]))begin
                        is_qj[i] <= 0;
                        vj[i] <= alu_val;
                    end
                    if(is_qk[i] && (alu_robid == qk[i]))begin
                        is_qk[i] <= 0;
                        vk[i] <= alu_val;
                    end
                end
                if(lsb_valid)begin
                    if(is_qj[i] && (lsb_robid == qj[i]))begin
                        is_qj[i] <= 0;
                        vj[i] <= lsb_val;
                    end
                    if(is_qk[i] && (lsb_robid == qk[i]))begin
                        is_qk[i] <= 0;
                        vk[i] <= lsb_val;
                    end
                end
            end
        end
    end
end
endmodule