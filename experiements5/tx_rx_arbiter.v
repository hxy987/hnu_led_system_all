// =================================================================
// 湖南大学 CSEE EC C301 - 综合选题3
// 文件功能：底层串行收发优先级仲裁器 (Rx 优先策略)
// =================================================================

module tx_rx_arbiter (
    input               clk,           // 50MHz 系统时钟
    input               nrst,          // 低电平有效复位
    
    // 外部主动发送请求接口
    input               tx_req,        // 外部发起的发送请求
    input       [7:0]   tx_data_in,    // 外部待发送的原始数据
    
    // 连接底层 uart_rx 模块接口
    input               rx_ready,      // 来自 uart_rx 的单字节接收就绪
    input       [7:0]   SBUF_rx,       // 来自 uart_rx 的单字节数据
    
    // 连接底层 uart_tx 模块接口
    input               tx_busy,       // 来自 uart_tx 的忙状态标志
    output reg          tx_en,         // 驱动 uart_tx 的使能触发信号(下降沿有效)
    output reg  [7:0]   tx_data_out,   // 交付给 uart_tx 的待发送数据
    
    // 仲裁后的数据交付总线（送至后级解析模块）
    output reg  [7:0]   arb_rx_data,   // 仲裁滤除冲突后安全合法的接收字节
    output reg          arb_rx_valid   // 仲裁后安全合法的接收就绪脉冲
);

    // 仲裁状态机
    localparam ARB_IDLE     = 2'b00;   // 总线空闲，等待收发请求
    localparam ARB_PRIO_RX  = 2'b01;   // 优先处理接收数据结算
    localparam ARB_TRIG_TX  = 2'b10;   // 响应并触发串口发送

    reg [1:0] state;
    reg [7:0] tx_data_buf;             // 发送数据暂存缓冲区
    reg       tx_pending;              // 发送请求挂起登记标志

    // 1. 发送请求登记器 (防止在总线忙或处理接收时丢失外部发送请求)
    always @(posedge clk or negedge nrst) begin
        if (!nrst) begin
            tx_pending  <= 1'b0;
            tx_data_buf <= 8'd0;
        end else begin
            if (tx_req && !tx_busy) begin
                tx_pending  <= 1'b1;
                tx_data_buf <= tx_data_in; // 暂存发送数据
            end else if (state == ARB_TRIG_TX) begin
                tx_pending  <= 1'b0;       // 发送被响应，清除登记
            end
        end
    end

    // 2. 核心优先级仲裁状态机 (严格执行 Rx 优先于 Tx 策略)
    always @(posedge clk or negedge nrst) begin
        if (!nrst) begin
            state        <= ARB_IDLE;
            tx_en        <= 1'b1;      // uart_tx 下降沿有效，默认保持高电平
            tx_data_out  <= 8'd0;
            arb_rx_data  <= 8'd0;
            arb_rx_valid <= 1'b0;
        end else begin
            arb_rx_valid <= 1'b0;      // 缺省保持单周期脉冲特性
            tx_en        <= 1'b1;      // 缺省保持高电平

            case (state)
                ARB_IDLE: begin
                    if (rx_ready) begin
                        // 无论此时有没有 Tx 请求，一律优先压入接收状态机
                        state <= ARB_PRIO_RX;
                    end else if (tx_pending && !tx_busy) begin
                        // 只有在完全没有 Rx 请求的绝对安全情况下，才响应 Tx
                        state <= ARB_TRIG_TX;
                    end
                end

                ARB_PRIO_RX: begin
                    // 结算接收数据，将其安全移交给后级解析器
                    arb_rx_data  <= SBUF_rx;
                    arb_rx_valid <= 1'b1;      // 激发一个干净的输出脉冲
                    state        <= ARB_IDLE;  // 处理完毕返回空闲
                end

                ARB_TRIG_TX: begin
                    // 触发物理 uart_tx 模块发送
                    tx_data_out <= tx_data_buf;
                    tx_en       <= 1'b0;       // 拉低，制造下降沿触发物理发送
                    state       <= ARB_IDLE;   // 退出，等待物理模块自主发送完毕
                end

                default: state <= ARB_IDLE;
            endcase
        end
    end

endmodule