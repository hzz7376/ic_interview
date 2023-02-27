`timescale 1ns / 1ps
////////////////////////////////////////////////////////////////////////////////////
//// Company: 
//// Engineer: 
//// 
//// Create Date: 2023/02/26 09:59:00
//// Design Name: 
//// Module Name: axi_stream_insert_header
//// Project Name: 
//// Target Devices: 
//// Tool Versions: 
//// Description: 
//// 
//// Dependencies: 
//// 
//// Revision:
//// Revision 0.01 - File Created
//// Additional Comments:
//// 
////////////////////////////////////////////////////////////////////////////////////

module axi_stream_insert_header #(
    parameter DATA_WD = 32,
    parameter DATA_BYTE_WD = DATA_WD / 8,
    parameter BYTE_CNT_WD = $clog2(DATA_BYTE_WD)
) (
    input clk,
    input rst_n,
    // AXI Stream input original data
    input valid_in,
    input [DATA_WD-1 : 0] data_in,
    input [DATA_BYTE_WD-1 : 0] keep_in,
    input last_in,
    output ready_in,
    // AXI Stream output with header inserted
    output valid_out,
    output [DATA_WD-1 : 0] data_out,
    output [DATA_BYTE_WD-1 : 0] keep_out,
    output last_out,
    input ready_out,
    // The header to be inserted to AXI Stream input
    input valid_insert,
    input [DATA_WD-1 : 0] header_insert,
    input [DATA_BYTE_WD-1 : 0] keep_insert,
    input [BYTE_CNT_WD : 0] byte_insert_cnt,
    output ready_insert
);

parameter IDLE = 4'b0001;
parameter HAEDER_INSERT = 4'b0010;
parameter WAIT_READYOUT = 4'b0100;
parameter AXIS_OUT = 4'b1000;

reg [3:0] state;
reg [3:0] next_state;
reg [1:0] in_index;//将输入数据暂存至mem的索引
reg [DATA_WD-1:0] mem [0:4];//缓存输入axis数据

assign valid_out = (state == AXIS_OUT)?1'b1:1'b0;
    
reg ready_in_reg;
reg ready_insert_reg;
    
//always @(posedge clk or negedge rst_n) begin
//    if((!rst_n)||(valid_in && ready_in_reg && last_in))
//        ready_insert_reg <= 'd1;
//    else if(valid_insert && ready_insert_reg)
//        ready_insert_reg<='d0;
//end

always @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        ready_insert_reg<='d0;
    else begin
        if(next_state == IDLE)
            ready_insert_reg <= 'd1;
        else 
            ready_insert_reg<='d0;
    end
end  

    
always @(posedge clk or negedge rst_n) begin
if(!rst_n)
    ready_in_reg <= 'd0;
else if(next_state == HAEDER_INSERT || next_state==AXIS_OUT)
    ready_in_reg<='d1;
else
    ready_in_reg<='d0;
end

always @(posedge clk or negedge rst_n) begin
if(!rst_n)begin
    state <= IDLE;
end 
else begin
    state <= next_state;
end
end

always @(*) begin
    next_state = IDLE;
    case (state)
        IDLE:begin
            if(valid_insert && ready_insert_reg)//header准备好后，接受header
                next_state = HAEDER_INSERT;
            else 
                next_state = IDLE;     
        end

        HAEDER_INSERT:begin
            if(ready_out && in_index == 2'd3)
                next_state = AXIS_OUT;
            else if(in_index == 2'd3)
                next_state = WAIT_READYOUT;
            else
                next_state = HAEDER_INSERT;     
        end

        WAIT_READYOUT:begin
            if(valid_in && ready_out)//等待输出ready
                next_state = AXIS_OUT;
            else 
                next_state = WAIT_READYOUT;     
        end

        AXIS_OUT:begin
            if(last_out)//输出流水
                next_state = IDLE;
            else 
                next_state = AXIS_OUT;     
        end
        
        default: next_state = IDLE;
    endcase    
end

//对byte_insert_cnt和keep_insert暂存
reg [BYTE_CNT_WD : 0] byte_insert_cnt_reg;
reg [DATA_BYTE_WD-1 : 0] keep_insert_reg;
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)
    begin
        byte_insert_cnt_reg <= 'b0;
        keep_insert_reg <= 'b0;
    end 
    else if(valid_insert && ready_insert_reg) 
    begin
        byte_insert_cnt_reg <= byte_insert_cnt;
        keep_insert_reg <= keep_insert;
    end 
    else 
    begin
        byte_insert_cnt_reg <= byte_insert_cnt_reg;
        keep_insert_reg <= keep_insert_reg;
    end
end

reg [DATA_BYTE_WD-1 : 0] keepin_last;
reg[4:0] axis_in_valid_cnt;//记录输入axis数据的有效拍数

integer k;
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)
    begin
        in_index <= 2'd0;
        axis_in_valid_cnt <= 5'b0;
        keepin_last <= 'b0; 
        for(k=0;k<=4;k=k+1) 
           mem[k] <= 32'b0;        
    end 
    else if(valid_insert && ready_insert_reg && in_index=='d0) 
    begin//存入header
        in_index <= in_index + 1'b1;
        mem[in_index] <= header_insert;
        axis_in_valid_cnt <= 5'b0;//axis_in_valid_cnt只记data的拍数，不计header
        keepin_last <= 'b0;
    end 
    else if (valid_in && ready_in_reg && last_in) 
    begin//最后一拍数据，保存最后一拍的keep
        in_index <= in_index + 1'b1;
        mem[in_index] <= data_in;
        axis_in_valid_cnt <= axis_in_valid_cnt + 1'b1;
        keepin_last <= keep_in;
    end 
    else if (valid_in && ready_in_reg) 
    begin//输入流水
        in_index <= in_index + 1'b1;
        mem[in_index] <= data_in;
        axis_in_valid_cnt <= axis_in_valid_cnt + 1'b1;
        keepin_last <= keepin_last;    
    end 
    else 
    begin
        in_index <= in_index;
        axis_in_valid_cnt <= axis_in_valid_cnt;
        keepin_last <= keepin_last;
    end
end

//对最后一拍数据的有效字节数进行计数
reg [BYTE_CNT_WD:0] keepin_last_count;
always@(posedge clk or negedge rst_n)
begin
    if(~rst_n)
    begin
        keepin_last_count<='d0;
    end
    else
    begin
        if(last_in)
        begin
            if(keep_in==4'b1000)
            keepin_last_count<='d1;
            else if(keep_in==4'b1100)
            keepin_last_count<='d2;
            else if(keep_in==4'b1110)
            keepin_last_count<='d3;
            else if(keep_in==4'b1111)
            keepin_last_count<='d4;
        end
    end
end

//如果帧头的有效字节数+数据最后一拍的有效字节数>4，则输出axis数据的拍数与输入axis数据的拍数相等
//否则输出axis数据的拍数=输入axis数据的拍数+1
wire [4:0] axis_out_valid_num ;
assign axis_out_valid_num = (keepin_last_count+byte_insert_cnt_reg>DATA_BYTE_WD)?axis_in_valid_cnt+1'b1:axis_in_valid_cnt;

reg [2*DATA_WD-1 : 0] data_out_reg;
reg [DATA_BYTE_WD-1 : 0] keep_out_reg;
reg last_out_reg;
reg [4:0]axis_out_cnt;

reg [1:0] out_index;
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        data_out_reg <= 'b0;
        keep_out_reg <= 'b0;
        last_out_reg <= 1'b0;
        out_index <= 'b0;
        axis_out_cnt <= 'b0;
    end else if((state==HAEDER_INSERT || state==WAIT_READYOUT) && next_state == AXIS_OUT) begin//输出header
        data_out_reg <= {mem[out_index],mem[out_index+1]} << (DATA_BYTE_WD - byte_insert_cnt)*8;
        keep_out_reg <= {DATA_BYTE_WD{1'b1}};
        last_out_reg <= 1'b0;
        out_index <= out_index + 1'b1;
        axis_out_cnt <= axis_out_cnt+1'b1;
    end else if (valid_out && ready_out) begin
        data_out_reg <= {mem[out_index],mem[out_index+1]} << (DATA_BYTE_WD - byte_insert_cnt)*8;//输出流水，最后一个数时拉高last，并且对keep进行赋值
        out_index <= out_index + 1'b1;
        axis_out_cnt <= axis_out_cnt+1'b1;
        if (axis_out_cnt == axis_out_valid_num-1'b1) begin//最后一拍
        last_out_reg <= 1'b1;
        keep_out_reg <= {keep_insert_reg,keepin_last} << (DATA_BYTE_WD - byte_insert_cnt);            
        end else begin                                                                                                                                           
        last_out_reg <= 1'b0;
        keep_out_reg <= {DATA_BYTE_WD{1'b1}};               
        end
    end else begin
        data_out_reg <= data_out_reg;
        keep_out_reg <= keep_out_reg;
        last_out_reg <= 1'b0;
        out_index <= 'b0;
        axis_out_cnt <= 'b0;
    end
end

assign data_out = data_out_reg[2*DATA_WD-1:DATA_WD];
assign keep_out = keep_out_reg;
assign last_out = last_out_reg;
assign ready_in = ready_in_reg;
assign ready_insert = ready_insert_reg;

endmodule