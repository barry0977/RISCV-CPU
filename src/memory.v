`include "const.v"

module MemoryController(
    input wire clk_in,
    input wire rst_in,
    input wire rdy_in,

    //与ram交互
    input  wire [ 7:0]          mem_din,		// data input bus
    output reg  [ 7:0]          mem_dout,		// data output bus
    output reg  [31:0]          mem_a,			// address bus (only 17:0 is used)
    output reg                  mem_wr,			// write/read signal (1 for write)

    //与ICache交互
    input  wire ic_mem_ask,
    input  wire [31:0] ic_mem_addr,
    output reg  ic_mem_valid,
    output reg  [31:0] ic_mem_inst,

    //与LSB交互
    input  wire lsb_request,
    input  wire lsb_lors, //0-load,1-store
    input  wire [5:0] lsb_mem_op,
    input  wire [31:0] lsb_mem_addr,
    input  wire [31:0] lsb_mem_data,
    output reg  lsb_mem_valid,
    output reg  [31:0] lsb_mem_val
);

reg [2:0] total_size;//总共需要读写的字节数
reg [2:0] cur_size;//已经完成的字节数
reg [2:0] state;//0-空闲,1-load,2-store,3-fetch,4-暂停（一周期）
//优先处理LSB的请求，再处理ICache的请求

always @(posedge clk_in)begin
    if(rst_in)begin
        total_size <= 0;
        cur_size <= 0;
        state <= 0;
        mem_dout <= 0;
        mem_a <= 0;
        mem_wr <= 0;
        ic_mem_valid <= 0;
        ic_mem_inst <= 0;
        lsb_mem_valid <= 0;
        lsb_mem_val <= 0;
    end
    else if(rdy_in)begin
        case(state)
            0:begin //空闲
                if(lsb_request)begin
                    if(!lsb_lors)begin //load
                        if(lsb_mem_op == `Lb || lsb_mem_op == `Lbu)begin
                            total_size <= 1;
                        end
                        else if(lsb_mem_op == `Lh || lsb_mem_op == `Lhu)begin
                            total_size <= 2;
                        end
                        else begin
                            total_size <= 4;
                        end
                        cur_size <= 0;
                        state <= 1;
                        mem_dout <= 0;
                        mem_a <= lsb_mem_addr;
                        mem_wr <= 0;
                    end
                    else begin //store
                        if(lsb_mem_op == `Sb)begin
                            total_size <= 1;
                        end
                        else if(lsb_mem_op == `Sh)begin
                            total_size <= 2;
                        end
                        else begin
                            total_size <= 4;
                        end
                        cur_size <= 0;
                        state <= 2;
                        mem_dout <= 0;
                        mem_a <= 0;
                        mem_wr <= 0;
                    end
                end
                else if(ic_mem_ask)begin
                    state <= 3;
                    mem_dout <= 0;
                    mem_a <= ic_mem_addr;
                    mem_wr <= 0;
                    total_size <= 4;
                    cur_size <= 0;
                end
                else begin
                    state <= 0;
                    mem_dout <= 0;
                    mem_a <= 0;
                    mem_wr <= 0;
                    total_size <= 0;
                    cur_size <= 0;
                end
                lsb_mem_valid <= 0;
                ic_mem_valid <= 0;
            end
            1:begin //load
                mem_wr <= 0;
                if(cur_size == 1)begin //因为MemCtrl发送信号后，下一周期Mem才会收到，再下个周期才会返回，因此从cur_size为1开始获取
                    lsb_mem_val[7:0] <= mem_din;
                end
                else if(cur_size == 2)begin
                    lsb_mem_val[15:8] <= mem_din;
                end
                else if(cur_size == 3)begin
                    lsb_mem_val[23:16] <= mem_din;
                end
                else if(cur_size == 4)begin
                    lsb_mem_val[31:24] <= mem_din;
                end

                if(cur_size == total_size)begin
                    lsb_mem_valid <= 1;
                    state <= 4;
                    total_size <= 0;
                    cur_size <= 0;
                    mem_dout <= 0;
                    mem_a <= 0;
                    mem_wr <= 0;
                    if(lsb_mem_op == `Lbu)begin // 无符号扩展
                        lsb_mem_val[31:8] <= 24'b0;
                    end
                    else if(lsb_mem_op == `Lb)begin // 符号扩展
                        lsb_mem_val[31:8] <= {24{mem_din[7]}};
                    end
                    else if(lsb_mem_op == `Lhu)begin // 无符号扩展
                        lsb_mem_val[31:16] <= 16'b0;
                    end
                    else if(lsb_mem_op == `Lh)begin //符号扩展
                        lsb_mem_val[31:16] <= {16{mem_din[7]}};
                    end
                end
                else begin
                    cur_size <= cur_size + 1;
                    mem_a <= mem_a + 1;
                end
            end
            2:begin //store
                mem_wr <= 1;
                if(cur_size == 0)begin //要在前一个周期先把要写的内容发给Mem,因此是从cur_size=0开始
                    mem_dout <= lsb_mem_data[7:0];
                end
                else if(cur_size == 1)begin
                    mem_dout <= lsb_mem_data[15:8];
                end
                else if(cur_size == 2)begin
                    mem_dout <= lsb_mem_data[23:16];
                end
                else if(cur_size == 3)begin
                    mem_dout <= lsb_mem_data[31:24];
                end

                if(cur_size == total_size)begin //cur_size = 4时,正好写完
                    lsb_mem_valid <= 1;
                    state <= 4;
                    total_size <= 0;
                    cur_size <= 0;
                    mem_dout <= 0;
                    mem_a <= 0;
                    mem_wr <= 0;
                end
                else begin
                    cur_size <= cur_size + 1;
                    mem_a <= cur_size == 0 ? lsb_mem_addr : mem_a + 1;//cur_size=0时传入第一个值，地址先不加1
                end
                // if(lsb_mem_addr != 196608 && lsb_mem_addr != 196612)begin
                //     mem_wr <= 1;
                //     if(cur_size == 0)begin //要在前一个周期先把要写的内容发给Mem,因此是从cur_size=0开始
                //         mem_dout <= lsb_mem_data[7:0];
                //     end
                //     else if(cur_size == 1)begin
                //         mem_dout <= lsb_mem_data[15:8];
                //     end
                //     else if(cur_size == 2)begin
                //         mem_dout <= lsb_mem_data[23:16];
                //     end
                //     else if(cur_size == 3)begin
                //         mem_dout <= lsb_mem_data[31:24];
                //     end

                //     if(cur_size == total_size)begin //cur_size = 4时,正好写完
                //         lsb_mem_valid <= 1;
                //         state <= 4;
                //         total_size <= 0;
                //         cur_size <= 0;
                //         mem_dout <= 0;
                //         mem_a <= 0;
                //         mem_wr <= 0;
                //     end
                //     else begin
                //         cur_size <= cur_size + 1;
                //         mem_a <= cur_size == 0 ? lsb_mem_addr : mem_a + 1;//cur_size=0时传入第一个值，地址先不加1
                //     end
                // end
                // else begin
                //     state <= 0;
                // end
            end
            3:begin //fetch
                mem_wr <= 0;
                if(cur_size == 1)begin
                    ic_mem_inst[7:0] <= mem_din;
                end
                else if(cur_size == 2)begin
                    ic_mem_inst[15:8] <= mem_din;
                end
                else if(cur_size == 3)begin
                    ic_mem_inst[23:16] <= mem_din;
                end
                else if(cur_size == 4)begin
                    ic_mem_inst[31:24] <= mem_din;
                end

                if(cur_size == 4)begin
                    ic_mem_valid <= 1;
                    state <= 4;
                    total_size <= 0;
                    cur_size <= 0;
                    mem_dout <= 0;
                    mem_a <= 0;
                    mem_wr <= 0;
                end
                else begin
                    cur_size <= cur_size + 1;
                    mem_a <= mem_a + 1;
                end
            end
            4:begin //暂停(LSB和ICache在该周期才会收到结果，从而修改valid为0，因此得暂停一周期等待)
                state <= 0;//下一周期恢复正常工作
                lsb_mem_valid <= 0;
                ic_mem_valid <= 0;
            end
        endcase
    end
end
endmodule