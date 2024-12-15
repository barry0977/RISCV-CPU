·include "const.v"

module ReorderBuffer(
    input wire clk_in,
    input wire rst_in,
    input wire rdy_in,

    //从Decoder获取的信息
    input wire inst_valid,//是否有指令传入
    input wire inst_ready,
    input wire [2:0] inst_type,
    input wire [4:0] inst_rd,
    input wire [31:0] inst_value,
    input wire [31:0] inst_pc,

    //RS执行完成的结果
    input wire rs_ready,
    input wire [`RoB_addr-1:0] rs_RoBindex,
    input wire [31:0] rs_value,

    //LSB执行完成的结果
    input wire lsb_ready,
    input wire [`RoB_addr-1:0] lsb_RoBindex,
    input wire [31:0] lsb_value,

    //给RF更新
    

    //提交时,通过CDB广播给所有元件
    output wire [31:0] cdb_value,
    output wire [`RoB_addr-1:0] cdb_RoBindex,
    output wire [4:0] cdb_regid,

    //是否已满
    output wire RoB_full,

    //分支预测错误，发出clear信号
    output reg clear
);

reg                 ready[`RoB_size-1:0];
reg [2:0]           RoBtype[`RoB_size-1:0];
reg                 busy[`RoB_size-1:0];
reg [4:0]           dest[`RoB_size-1:0];//对应的目标寄存器
reg [31:0]          value[`RoB_size-1:0];//计算出来的值
reg []
reg [`RoB_addr-1:0] head,tail;

wire empty,full;
assign full = (rear + 1) % `RoB_size == front;
assign empty = front == rear;

always @(posedge clk_in) begin
    if(rst_in)begin
        //清除RoB
        head <= 0;
        rear <= 0;
        for(int i = 0; i < `RoB_size; i++)begin
            ready[i] <= 0;
            busy[i] <= 0;
            value[i] <= 0;
            dest[i] <= 0;
        end
    end
    else if(rdy_in)begin
        //加入RoB末尾
        if(inst_valid)begin
            tail <= (tail + 1) % `RoB_size;
            busy[tail] <= 1;
            ready[tail] <= inst_ready;
            dest[tail] <= inst_rd;
            value[tail] <= inst_value;
        end
        //如果头部ready，则commit
        if(busy[head]&&ready[head])begin
            head <= (head + 1) % `RoB_size;
            busy[head] <= 0;
            ready[head] <= 0;
            case
        end
    end
end
endmodule