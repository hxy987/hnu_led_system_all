module uart_tx(
    input         clk,        // 50MHz时钟
    input         rst_n,      // 低电平复位
    input         tx_en,      // 下降沿触发
    input  [7:0]  data_in,    // 待发送数据
    output reg    tx_dout,    // 串口输出
    output reg    tx_busy     // 忙标志
);

// 115200波特率，50MHz下计数到433
parameter BAUD_CNT = 13'd433;

reg [12:0] baud_cnt;
wire baud_en;

always @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        baud_cnt <= 13'd0;
    else if(tx_busy && baud_cnt == BAUD_CNT)
        baud_cnt <= 13'd0;
    else if(tx_busy)
        baud_cnt <= baud_cnt + 13'd1;
    else
        baud_cnt <= 13'd0;
end

assign baud_en = (baud_cnt == BAUD_CNT);

reg [3:0] bit_cnt;
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        bit_cnt <= 4'd0;
    else if(!tx_busy)
        bit_cnt <= 4'd0;
    else if(baud_en)
        bit_cnt <= bit_cnt + 4'd1;
end

reg [7:0] shift_reg;
reg tx_en_sync1, tx_en_sync2;
wire tx_en_neg_edge;

// 按键同步
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        tx_en_sync1 <= 1'b1;
        tx_en_sync2 <= 1'b1;
    end else begin
        tx_en_sync1 <= tx_en;
        tx_en_sync2 <= tx_en_sync1;
    end
end

assign tx_en_neg_edge = tx_en_sync2 & ~tx_en_sync1;

// 发送主控
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        tx_dout <= 1'b1;
        tx_busy <= 1'b0;
        shift_reg <= 8'd0;
    end
    else if(tx_en_neg_edge && !tx_busy) begin
        // 只在这里拉低起始位，后面case里不再重复设置
        tx_busy <= 1'b1;
        shift_reg <= data_in;
        tx_dout <= 1'b0; // 起始位（只拉低一次）
    end
    else if(baud_en && tx_busy) begin
        case(bit_cnt)
            // 0: 起始位已经拉低，这里直接发bit0
            4'd0: tx_dout <= shift_reg[0];
            4'd1: tx_dout <= shift_reg[1];
            4'd2: tx_dout <= shift_reg[2];
            4'd3: tx_dout <= shift_reg[3];
            4'd4: tx_dout <= shift_reg[4];
            4'd5: tx_dout <= shift_reg[5];
            4'd6: tx_dout <= shift_reg[6];
            4'd7: tx_dout <= shift_reg[7];
            4'd8: tx_dout <= 1'b1; // 停止位
            4'd9: begin
                tx_dout <= 1'b1;
                tx_busy <= 1'b0;
            end
        endcase
    end
end

endmodule