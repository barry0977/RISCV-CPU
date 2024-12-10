`include "const.v"

module ALU(
    input wire[31:0] rs1,
    input wire[31:0] rs2,
    input wire[5:0] op,

    output reg [31:0] result,
    output reg        valid
);

always @(*)begin
    result = 0;
    if(op > 0)begin
        valid = 1;
    end else begin 
        valid = 0;
    end
    case(op)
        `Lui:begin
            result = rs1;
        end
        `Auipc:begin
            result = rs1 + rs2;
        end
        `Jal:begin
            result = rs2 + 4;
        end
        `Beq:begin
            if(rs1 == rs2)begin
                result = 1;
            end
        end
        `Bne:begin
            if(rs1 != rs2)begin
                result = 1;
            end
        end
        `Blt:begin
            if($signed(rs1) < $signed(rs2))begin
                result = 1;
            end
        end
        `Bge:begin
            if($signed(rs1) >= $signed(rs2))begin
                result = 1;
            end
        end
        `Bltu:begin
            if(rs1 < rs2)begin
                result = 1;
            end
        end
        `Bgeu:begin
            if(rs1 >= rs2)begin
                result = 1;
            end
        end
        `Addi:begin
            result = rs1 + rs2;
        end
        `Slti:begin
            if($signed(rs1) < $signed(rs2))begin
                result = 1;
            end
        end
        `Sltiu:begin
            if(rs1 < rs2)begin
                result = 1;
            end
        end
        `Andi:begin
            result = rs1 & rs2;
        end
        `Ori:begin
            result = rs1 | rs2;
        end
        `Xori:begin
            result = rs1 ^ rs2;
        end
        `Slli:begin
            result = rs1 << rs2[4:0];
        end
        `Srli:begin
            result = rs1 >> rs2[4:0];
        end
        `Srai:begin
            result = $signed(rs1) >> rs2[4:0];
        end
        `Add:begin
            result = rs1 + rs2;
        end
        `Slt:begin
            result = $signed(rs1) < $signed(rs2);
        end
        `Sltu:begin
            result = rs1 < rs2;
        end
        `And:begin
            result = rs1 & rs2;
        end
        `Or:begin
            result = rs1 | rs2;
        end
        `Xor:begin
            result = rs1 ^ rs2;
        end
        `Sll:begin
            result = $signed(rs1) << rs2;
        end
        `Srl:begin
            result = rs1 >> rs2;
        end
        `Sra:begin
            result = $signed(rs1) >> rs2;
        end
        `Sub:begin
            result = rs1 - rs2;
        end
    endcase
end
endmodule