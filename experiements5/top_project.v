// =================================================================
// 湖南大学 CSEE EC C301 - 综合选题3
// 文件功能：系统大集成顶层模块 - 闭环装配总线
// =================================================================

module top_project (
    input               clk,           // 物理引脚：50MHz 主时钟 (PIN_E1) [cite: 402, 452]
    input               rst_n,         // 物理引脚：全局硬件复位 (PIN_L2) [cite: 402, 452]
    
    // 物理无线蓝牙串口引脚 (PMOD接口) [cite: 458, 528]
    input               uart_rx,       // 蓝牙接收线 FPGA <- PMOD RX [cite: 458, 528]
    output              uart_tx,       // 蓝牙发送线 FPGA -> PMOD TX [cite: 119]
    
    // 板载手动触发按键反馈
    input               key_feedback,  // 用户按键触发向手机发送状态反馈 [cite: 459]
    
    // 物理单线串行彩灯输出接口
    output              led_out,       // 物理引脚：WS2812 Board 1 数据输出 (PIN_T2) [cite: 402]
    output              led_out_b2,    // V4 物理引脚：WS2812 Board 2 数据输出 (PIN_T3)
    input               feedback_b2    // V4 Board 2 末级环回监测 (PIN_P1)
);

    // 内部连线网络定义
    wire [7:0]  w_sbuf_rx;
    wire        w_rx_ready;
    wire        w_tx_busy;
    wire        w_tx_en;
    wire [7:0]  w_tx_data_out;
    
    wire [7:0]  w_arb_rx_data;
    wire        w_arb_rx_valid;
    
    wire [7:0]  w_ctrl_mode;
    wire [7:0]  w_ctrl_color;
    wire [7:0]  w_ctrl_brightness;
    wire [7:0]  w_ctrl_param;
    
    wire [7:0]  w_led_data_in10;
    wire [7:0]  w_led_data_in32;
    wire [7:0]  w_led_data_in10_b2; // V4: Board 2 数据总线
    wire [7:0]  w_led_data_in32_b2;
    wire        w_driver_mode;
    wire [3:0]  w_inner_brightness;
    wire [3:0]  w_outer_brightness;

    // 按键同步消抖链路 (针对板载发送按键)
    reg k_sync1, k_sync2;
    wire k_neg_edge;
    always @(posedge clk) begin
        k_sync1 <= key_feedback;
        k_sync2 <= k_sync1;
    end
    assign k_neg_edge = k_sync2 & ~k_sync1; // 捕获手动按键触发脉冲

    // =================================================================
    // 1. 物理层单字节串口接收模块（实例化你编写的优秀的 uart_rx） [cite: 843]
    // =================================================================
    uart_rx #(
        .CLK_FREQ(50_000_000),
        .BAUD_RATE(115200)
    ) u_physics_rx (
        .clk(clk),
        .nrst(rst_n),
        .rx(uart_rx),
        .SBUF_rx(w_sbuf_rx),
        .rx_ready(w_rx_ready)
    );

    // =================================================================
    // 2. 物理层单字节串口发送模块（实例化你编写的优秀的 uart_tx） 
    // =================================================================
    uart_tx u_physics_tx (
        .clk(clk),
        .rst_n(rst_n),
        .tx_en(w_tx_en),                 // 挂接在仲裁器的使能输出上
        .data_in(w_tx_data_out),         // 挂接在仲裁器的发送数据上
        .tx_dout(uart_tx),
        .tx_busy(w_tx_busy)
    );

    // =================================================================
    // 3. 收发冲突优先级仲裁器模块（连接收发两端，实行 Rx 绝对优先策略） 
    // =================================================================
    tx_rx_arbiter u_system_arbiter (
        .clk(clk),
        .nrst(rst_n),
        .tx_req(k_neg_edge),             // 挂接按键下降沿触发信号 [cite: 459]
        .tx_data_in(8'hC3),              // 根据讲义第7页步骤1要求，固定反馈握手码 0xC3 [cite: 722]
        .rx_ready(w_rx_ready),
        .SBUF_rx(w_sbuf_rx),
        .tx_busy(w_tx_busy),
        .tx_en(w_tx_en),
        .tx_data_out(w_tx_data_out),
        .arb_rx_data(w_arb_rx_data),     // 输出过滤完冲突的纯净安全数据
        .arb_rx_valid(w_arb_rx_valid)
    );

    // =================================================================
    // 4. 上层事务控制协议解析状态机（双层状态机中的上层核心） 
    // =================================================================
    cmd_parser u_top_fsm (
        .clk(clk),
        .nrst(rst_n),
        .rx_data(w_arb_rx_data),
        .rx_ready(w_arb_rx_valid),
        .ctrl_mode(w_ctrl_mode),         // 输出锁存的全局控制模式
        .ctrl_color(w_ctrl_color),       // 输出锁存的全局颜色 (V3)
        .ctrl_brightness(w_ctrl_brightness), // 输出锁存的全局亮度 (V3)
        .ctrl_param(w_ctrl_param)        // 输出锁存的全局参数 (Byte 4)
    );

    // =================================================================
    // 5. 彩灯多场景效果实时动态发生器 
    // =================================================================
    effect_generator u_effect_core (
        .clk(clk),
        .nrst(rst_n),
        .ctrl_mode(w_ctrl_mode),
        .ctrl_color(w_ctrl_color),           // V3: 全局颜色输入
        .ctrl_brightness(w_ctrl_brightness), // V3: 全局亮度输入
        .ctrl_param(w_ctrl_param),
        .led_data_in10(w_led_data_in10), // 生成直接交付给底层驱动的数据流
        .led_data_in32(w_led_data_in32),
        .led_data_in10_b2(w_led_data_in10_b2), // V4: Board 2 数据流
        .led_data_in32_b2(w_led_data_in32_b2),
        .driver_mode(w_driver_mode),
        .inner_brightness(w_inner_brightness),
        .outer_brightness(w_outer_brightness)
    );

    // =================================================================
    // 6. 底层串行硬件单线驱动模块 #1 — Board 1 (板载 8 LED)
    // =================================================================
    my_ws2812 u_hardware_driver_b1 (
        .clk(clk),
        .rst_n(rst_n),
        .inner_brightness(w_inner_brightness),
        .outer_brightness(w_outer_brightness),
        .led_data_in10(w_led_data_in10),
        .led_data_in32(w_led_data_in32),
        .mode(w_driver_mode),
        .led_out(led_out)
    );

    // =================================================================
    // 7. 底层串行硬件单线驱动模块 #2 — Board 2 (外接 PMOD 8 LED) [V4 新增]
    // =================================================================
    my_ws2812 u_hardware_driver_b2 (
        .clk(clk),
        .rst_n(rst_n),
        .inner_brightness(w_inner_brightness),
        .outer_brightness(w_outer_brightness),
        .led_data_in10(w_led_data_in10_b2),
        .led_data_in32(w_led_data_in32_b2),
        .mode(w_driver_mode),
        .led_out(led_out_b2)
    );

endmodule