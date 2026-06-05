// =================================================================
// 湖南大学 CSEE EC C301 - 综合选题3
// 文件功能：上层事务控制状态机（FSM）- 3字节指令透传解析器
//           v2.0：增加帧头主动搜索自同步机制，彻底解决字节错位死锁问题
// =================================================================

module cmd_parser (
    input               clk,           // 50MHz 系统时钟
    input               nrst,          // 低电平有效复位

    // 连接底层单字节 uart_rx 模块接口
    input       [7:0]   rx_data,       // 来自 uart_rx 的 SBUF_rx
    input               rx_ready,      // 来自 uart_rx 的 rx_ready 脉冲

    // 解析完成的控制总线（输出给后级效果发生器）
    output reg  [7:0]   ctrl_mode,     // 当前控制模式锁存值
    output reg  [7:0]   ctrl_param     // 当前模式参数锁存值（如颜色或速度）
);

    // =================================================================
    // 改进状态机设计 (v2.0)：
    //   不再依赖"3字节严格对齐"假设，而是在字节流中主动搜索 0x5A 帧头，
    //   搜到后依次接收 mode 和 param，自动完成帧同步。
    //   任何杂散/碎片的中间字节都会被自动丢弃，永不发生永久性错位。
    // =================================================================
    localparam ST_WAIT_HEADER = 2'b00;  // 搜索 0x5A 帧头
    localparam ST_GET_MODE    = 2'b01;  // 接收第2字节（mode）
    localparam ST_GET_PARAM   = 2'b10;  // 接收第3字节（param），完成后立即更新输出

    reg [1:0] state;
    reg [7:0] mode_buf;                 // 暂存 mode 字节（等待 param 到达后一起更新）

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
    // 核心帧同步解析状态机
    //   协议格式：[0x5A] [mode] [param]（3字节，0x5A 为帧头魔数）
    //   行为：在任何状态下，只认 0x5A 作为帧起始标志，
    //         mode 和 param 字节即使值为 0x5A 也不会误触发重新同步
    //         （因为它们被当作合法数据直接接收，不会回到 WAIT_HEADER）。
    // =================================================================
    always @(posedge clk or negedge nrst) begin
        if (!nrst) begin
            state      <= ST_WAIT_HEADER;
            mode_buf   <= 8'd0;
            ctrl_mode  <= 8'h01;        // 默认模式：静态单色控制
            ctrl_param <= 8'h10;        // 默认参数：bit4=1 → 单灯绿色
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
                        // 接收 mode 字节并暂存（不区分其值，包括 0x5A 也直接当数据）
                        mode_buf <= rx_data;
                        state    <= ST_GET_PARAM;
                    end

                    ST_GET_PARAM: begin
                        // 接收 param 字节，与暂存的 mode 一同更新输出总线
                        ctrl_mode  <= mode_buf;
                        ctrl_param <= rx_data;
                        state      <= ST_WAIT_HEADER;  // 完成一帧，立即搜索下一帧
                    end

                    default: state <= ST_WAIT_HEADER;
                endcase
            end
        end
    end

endmodule