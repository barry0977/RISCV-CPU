`include "const.v"

module LoadStoreBuffer(
    input wire clk_in,
    input wire rst_in,
    input wire rdy_in,

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

    output wire full,

    //ALU结果更新
    input wire alu_valid,//有新结果更新
    input wire [`RoB_addr-1:0] alu_robid,
    input wire [31:0] alu_val,

    //与MemControl交互
    input wire mem_valid,
    input wire [31:0] mem_data,
    //LSB只进行load操作，store在RoB commit时进行
    output reg request,
    output reg [`LSB_addr-1:0] lsbid,
    output reg sign,//0-unsigned,1-signed
    output reg [1:0] mem_type,//0-byte,1-halfbyte,2-word
    output wire [31:0] mem_addr,

    //发送给RoB(仅store需要传输addr和data)
    output reg lsb_ready,
    output reg [31:0] lsb_addr,
    output reg [31:0] lsb_data,
    
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

wire ready_head;
reg  send_request;
wire new_has_rely1,new_has_rely2;
wire [31:0] new_val1,new_val2;

//判断同一周期新更新是否会更新依赖
assign new_has_rely1 = inst_has_rely1 && !(alu_valid && (alu_robid == inst_rely1)) && !(lsb_valid && (lsb_robid == inst_rely1));
assign new_has_rely2 = inst_has_rely2 && !(alu_valid && (alu_robid == inst_rely2)) && !(lsb_valid && (lsb_robid == inst_rely2));
assign new_val1 = !inst_has_rely1 ? inst_val1 : (alu_valid && (alu_robid == inst_rely1)) ? alu_val : (lsb_valid && (lsb_robid == inst_rely1)) ? lsb_val : 0;
assign new_val2 = !inst_has_rely2 ? inst_val2 : (alu_valid && (alu_robid == inst_rely2)) ? alu_val : (lsb_valid && (lsb_robid == inst_rely2)) ? lsb_val : 0;

assign ready_head = busy[head] && (!is_qj[head]) && (!is_qk[head]);
assign mem_addr = vj[head] + imm[head];

integer i;
always @(posedge clk_in)begin
    if(rst_in)begin
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
        //加入LSB
        if(inst_valid)begin
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
        //若head ready,则执行
        if(ready_head)begin
            //load
            if(op[head] >= `Lb && op[head] <= `Lhu)begin
                if(mem_valid)begin//已经获取数据，可以执行
                    send_request <= 0;
                    head <= head + 1;
                    busy[head] <= 0;
                    lsb_valid <= 1;
                    lsb_robid <= RoBindex[head];
                    lsb_val <= mem_data;
                    lsb_ready <= 1;
                end
                else begin//未获得数据，等待
                    if(!send_request)begin//还没发送请求
                        request <= 1;
                        send_request <= 1;
                        lsbid <= head;
                        sign = op[head] < `Lbu;
                        mem_type = op[head] == `Lw ? 2 : (op[head] == `Lb || op[head] == `Lbu) ? 0 : 1;
                    end
                    else begin
                        request <= 0;
                    end
                    lsb_ready <= 0;
                    lsb_valid <= 0;
                end
            end
            //store
            else begin
                head <= head + 1;
                busy[head] <= 0;
                lsb_ready <= 1;
                lsb_addr <= mem_addr;
                lsb_data <= vk[head];
                lsb_valid <= 0;
            end
        end
        else begin
            lsb_ready <= 0;
            lsb_valid <= 0;
        end
        //更新依赖
        for(i = 0; i < `LSB_size; i = i + 1)begin
            if(busy[i])begin
                if(alu_valid)begin
                    if(is_qj[i] && (alu_robid == qj[i]))begin
                        is_qj[i] <= 0;
                        vj[i] <= alu_val;
                    end
                    if(is_qj[i] && (alu_robid == qj[i]))begin
                        is_qk[i] <= 0;
                        vk[i] <= alu_val;
                    end
                end
                if(lsb_valid)begin
                    if(is_qj[i] && (lsb_robid == qj[i]))begin
                        is_qj[i] <= 0;
                        vj[i] <= lsb_val;
                    end
                    if(is_qj[i] && (lsb_robid == qj[i]))begin
                        is_qk[i] <= 0;
                        vk[i] <= lsb_val;
                    end
                end
            end
        end
    end
end
endmodule