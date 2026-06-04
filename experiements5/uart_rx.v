module uart_rx #(
    parameter CLK_FREQ  = 50_000_000,  
    parameter BAUD_RATE = 115200       
)(
    input  wire clk,
    input  wire nrst,
    input  wire rx,            
    output reg  [7:0] SBUF_rx, 
    output reg  rx_ready       
);

    localparam BAUD_CNT_MAX  = CLK_FREQ / BAUD_RATE;
    localparam BAUD_CNT_HALF = BAUD_CNT_MAX / 2;

    localparam STATE_IDLE  = 2'b00;
    localparam STATE_START = 2'b01; 
    localparam STATE_DATA  = 2'b10; 
    localparam STATE_STOP  = 2'b11; 

    reg [1:0]  state;
    reg [15:0] baud_cnt;  
    reg [2:0]  bit_cnt;   
    reg [7:0]  rx_data_r; 

    reg rx_d0, rx_d1, rx_d2;
    wire nedge_rx = rx_d2 & ~rx_d1;

    always @(posedge clk or negedge nrst) begin
        if (!nrst) begin
            rx_d0 <= 1; rx_d1 <= 1; rx_d2 <= 1;
        end else begin
            rx_d0 <= rx; rx_d1 <= rx_d0; rx_d2 <= rx_d1;
        end
    end

    always @(posedge clk or negedge nrst) begin
        if (!nrst) begin
            state     <= STATE_IDLE;
            baud_cnt  <= 0;
            bit_cnt   <= 0;
            rx_data_r <= 0;
            SBUF_rx   <= 0;
            rx_ready  <= 0;
        end else begin
            rx_ready <= 0; 

            case (state)
                STATE_IDLE: begin
                    baud_cnt <= 0;
                    if (nedge_rx) state <= STATE_START; 
                end
                
                STATE_START: begin
                    if (baud_cnt == BAUD_CNT_HALF) begin
                        if (rx_d1 == 0) begin // 确认真的是起始位
                            state    <= STATE_DATA;
                            baud_cnt <= 0;
                            bit_cnt  <= 0;
                        end else begin
                            state    <= STATE_IDLE; // 毛刺，回空闲
                        end
                    end else begin
                        baud_cnt <= baud_cnt + 1;
                    end
                end
                
                STATE_DATA: begin
                    if (baud_cnt == BAUD_CNT_MAX - 1) begin
                        baud_cnt <= 0;
                        if (bit_cnt == 7) state <= STATE_STOP;
                        else              bit_cnt <= bit_cnt + 1;
                    end else begin
                        baud_cnt <= baud_cnt + 1;
                        if (baud_cnt == BAUD_CNT_HALF) begin
                            rx_data_r[bit_cnt] <= rx_d1;
                        end
                    end
                end
                
                STATE_STOP: begin
                    // 【核心魔法：半停止位返回法】
                    // 不等完整的波特率周期，只要到了停止位的中心点，立刻结算并回到 IDLE！
                    // 这确保了状态机有绝对充足的时间去捕捉下一个无缝衔接的起始位。
                    if (baud_cnt == BAUD_CNT_HALF) begin
                        SBUF_rx  <= rx_data_r;
                        rx_ready <= 1;
                        state    <= STATE_IDLE; 
                    end else begin
                        baud_cnt <= baud_cnt + 1;
                    end
                end
                default: state <= STATE_IDLE;
            endcase
        end
    end

endmodule