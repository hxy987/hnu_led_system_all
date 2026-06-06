// =================================================================
// 湖南大学 CSEE EC C301 - 综合选题3
// 文件功能：上层事务控制状态机（FSM）- 5字节指令透传解析器
//           v3.0：升级为5字节协议 [0x5A, mode, color, brightness, param]
//           保留帧头主动搜索自同步机制
// =================================================================

module cmd_parser (
    input               clk,           // 50MHz 系统时钟
    input               nrst,          // 低电平有效复位

    // 连接底层单字节 uart_rx 模块接口
    input       [7:0]   rx_data,       // 来自 uart_rx 的 SBUF_rx
    input               rx_ready,      // 来自 uart_rx 的 rx_ready 脉冲

    // 解析完成的控制总线（输出给后级效果发生器）— V3: 5字节协议
    output reg  [7:0]   ctrl_mode,     // Byte 1: 控制模式 (0x01/0x02/0x03)
    output reg  [7:0]   ctrl_color,    // Byte 2: 全局颜色 (0x01=R, 0x02=G, 0x03=B)
    output reg  [7:0]   ctrl_brightness,// Byte 3: 全局亮度 (0x00~0xFF)
    output reg  [7:0]   ctrl_param     // Byte 4: LED掩码 / 速度 / 节拍参数
);

    // =================================================================
    // V3.0 状态机设计 (5字节协议)：
    //   在字节流中主动搜索 0x5A 帧头，搜到后依次接收 mode、color、
    //   brightness、param，全部收齐后一次性更新输出总线。
    //   任何杂散/碎片的中间字节都会被自动丢弃，永不发生永久性错位。
    // =================================================================
    localparam ST_WAIT_HEADER  = 3'b000;  // 搜索 0x5A 帧头
    localparam ST_GET_MODE     = 3'b001;  // 接收第2字节（mode）
    localparam ST_GET_COLOR    = 3'b010;  // 接收第3字节（color）
    localparam ST_GET_BRIGHT   = 3'b011;  // 接收第4字节（brightness）
    localparam ST_GET_PARAM    = 3'b100;  // 接收第5字节（param），完成后立即更新输出

    reg [2:0] state;
    reg [7:0] mode_buf;                 // 暂存 mode 字节
    reg [7:0] color_buf;                // 暂存 color 字节
    reg [7:0] bright_buf;               // 暂存 brightness 字节

    // =================================================================
    // 看门狗定时器 (50MHz / 50000 = 1ms 超时)
    //   若超过 1ms 无字节到达，强制回 ST_WAIT_HEADER 等待下一帧
    // =================================================================
    reg [15:0] wd_cnt;
    localparam WD_TIMEOUT = 16'd50000;

    always @(posedge clk or negedge nrst) begin
        if (!nrst) begin
            wd_cnt <= 16'd0;
        end else if (rx_ready) begin
            wd_cnt <= 16'd0;            // 每收到一个字节就喂狗
        end else if (wd_cnt < WD_TIMEOUT) begin
            wd_cnt <= wd_cnt + 16'd1;   // 空闲时持续计数
        end
    end

    // =================================================================
    // 核心帧同步解析状态机 (V3.0 — 5字节协议)
    //   协议格式：[0x5A] [mode] [color] [brightness] [param]
    //   行为：在任何状态下，只认 0x5A 作为帧起始标志，
    //         mode/color/brightness/param 字节即使值为 0x5A 也不会误触发重新同步
    //         （因为它们被当作合法数据直接接收，不会回到 WAIT_HEADER）。
    // =================================================================
    always @(posedge clk or negedge nrst) begin
        if (!nrst) begin
            state          <= ST_WAIT_HEADER;
            mode_buf       <= 8'd0;
            color_buf      <= 8'd0;
            bright_buf     <= 8'd0;
            ctrl_mode      <= 8'h01;        // 默认模式：独立灯珠控制
            ctrl_color     <= 8'h02;        // 默认颜色：绿色 (0x02=G)
            ctrl_brightness<= 8'h80;        // 默认亮度：中位 (~50%)
            ctrl_param     <= 8'h00;        // 默认参数：无LED点亮
        end else begin
            // 看门狗超时保护：非空闲状态超过1ms无数据 → 强制复位
            if (wd_cnt == WD_TIMEOUT && state != ST_WAIT_HEADER) begin
                state <= ST_WAIT_HEADER;
            end else if (rx_ready) begin
                case (state)
                    ST_WAIT_HEADER: begin
                        // 在字节流中搜索帧头魔数 0x5A
                        // 非 0x5A 的字节一律丢弃（可能是噪声/碎片/错位残留）
                        if (rx_data == 8'h5A)
                            state <= ST_GET_MODE;
                    end

                    ST_GET_MODE: begin
                        // 接收 mode 字节并暂存
                        mode_buf <= rx_data;
                        state    <= ST_GET_COLOR;
                    end

                    ST_GET_COLOR: begin
                        // 接收 color 字节并暂存
                        color_buf <= rx_data;
                        state     <= ST_GET_BRIGHT;
                    end

                    ST_GET_BRIGHT: begin
                        // 接收 brightness 字节并暂存
                        bright_buf <= rx_data;
                        state      <= ST_GET_PARAM;
                    end

                    ST_GET_PARAM: begin
                        // 接收 param 字节，与暂存的 mode/color/brightness 一同更新输出总线
                        ctrl_mode       <= mode_buf;
                        ctrl_color      <= color_buf;
                        ctrl_brightness <= bright_buf;
                        ctrl_param      <= rx_data;
                        state           <= ST_WAIT_HEADER;  // 完成一帧，立即搜索下一帧
                    end

                    default: state <= ST_WAIT_HEADER;
                endcase
            end
        end
    end

endmodule
