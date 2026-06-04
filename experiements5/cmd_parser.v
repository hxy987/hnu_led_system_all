// =================================================================
// 湖南大学 CSEE EC C301 - 综合选题3
// 文件功能：上层事务控制状态机（FSM）- 3字节指令透传解析器
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

    // 状态机状态定义
    localparam ST_IDLE   = 2'b00;      // 等待多字节数据拼装
    localparam ST_CHECK  = 2'b01;      // 校验帧头合法性
    localparam ST_UPDATE = 2'b10;      // 更新锁存控制寄存器

    reg [1:0]  state;
    reg [1:0]  byte_cnt;               // 多字节接收计数器
    reg [7:0]  packet_buffer [0:2];    // 3字节数据包暂存阵列

    // =================================================================
    // 0. 帧同步看门狗定时器 (50MHz / 50000 = 1ms 超时)
    //    目的：中途丢字节或收到杂散字节后，自动复位 byte_cnt，
    //         强制重新对齐到下一个帧头 0x5A，避免永久死锁
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
        // 达到 WD_TIMEOUT 后保持，直到 rx_ready 重新喂狗
    end

    // 1. 多字节数据包拼装暂存逻辑（含看门狗复位保护）
    always @(posedge clk or negedge nrst) begin
        if (!nrst) begin
            byte_cnt <= 2'd0;
            packet_buffer[0] <= 8'd0;
            packet_buffer[1] <= 8'd0;
            packet_buffer[2] <= 8'd0;
        end else if (rx_ready) begin
            packet_buffer[byte_cnt] <= rx_data;
            if (byte_cnt == 2'd2)
                byte_cnt <= 2'd0;      // 满3字节复位
            else
                byte_cnt <= byte_cnt + 2'd1;
        end else if (wd_cnt == WD_TIMEOUT) begin
            // 看门狗超时：超过1ms无字节到达 → 强制归零，等待下一帧
            byte_cnt <= 2'd0;
        end
    end

    // 2. 上层事务 FSM 状态变迁与逻辑核心（含看门狗保护）
    always @(posedge clk or negedge nrst) begin
        if (!nrst) begin
            state      <= ST_IDLE;
            ctrl_mode  <= 8'h01;       // 默认模式：静态单色控制
            ctrl_param <= 8'h10;       // 默认参数：纯绿色
        end else begin
            // 看门狗超时保护：若超过1ms无字节到达且不在IDLE，强制回IDLE
            if (wd_cnt == WD_TIMEOUT && state != ST_IDLE) begin
                state <= ST_IDLE;
            end else begin
                case (state)
                    ST_IDLE: begin
                        // 当在接收到第3个字节（索引2）且 rx_ready 触发时跳入校验
                        if (rx_ready && (byte_cnt == 2'd2))
                            state <= ST_CHECK;
                    end

                    ST_CHECK: begin
                        // 校验 packet_buffer[0] 是否等于自研 APP 的协议帧头 0x5A
                        if (packet_buffer[0] == 8'h5A)
                            state <= ST_UPDATE;
                        else
                            state <= ST_IDLE; // 帧头不对，视为垃圾毛刺，直接丢弃
                    end

                    ST_UPDATE: begin
                        // 锁存有效指令到全局控制总线
                        ctrl_mode  <= packet_buffer[1];
                        ctrl_param <= packet_buffer[2];
                        state      <= ST_IDLE; // 更新完成，返回空闲等待下一发
                    end

                    default: state <= ST_IDLE;
                endcase
            end
        end
    end

endmodule