module my_ws2812 (
    input               clk,             // 50MHz 系统时钟 (20ns)
    input               rst_n,           // 低电平有效复位
    input       [3:0]   inner_brightness,// 内群亮度 (LED 2,3,6,7) 16档 (0~15)
    input       [3:0]   outer_brightness,// 外群亮度 (LED 1,4,5,8) 16档 (0~15)
    input       [7:0]   led_data_in10,   // 模式0的数据 / 模式1的低组数据
    input       [7:0]   led_data_in32,   // 模式1的高组数据
    input               mode,            // 模式选择 (0:流水灯, 1:数码管组控)
    output reg          led_out          // 单线串行输出信号
);

    // ============================================================
    // 1. 时序参数定义 (基于 50MHz 时钟，周期 20ns)
    // ============================================================
    localparam T1H_MAX   = 6'd45;        // 1码高电平时间 (900ns)
    localparam T0H_MAX   = 6'd15;        // 0码高电平时间 (300ns)
    localparam BIT_TOTAL = 6'd62;        // 1个比特的总时钟周期数 (1.25us)
    localparam RST_COUNT = 16'd25000;    // 复位低电平时间 (500us >> 80us, 充足裕度防首次烧录不亮)

    // ============================================================
    // 2. 内部寄存器：帧起始锁存
    // ============================================================
    reg         mode_latched;
    reg [3:0]   inner_brightness_latched;
    reg [3:0]   outer_brightness_latched;
    reg [7:0]   data10_latched;
    reg [7:0]   data32_latched;
    // 内群 / 外群独立颜色通道值
    reg [7:0]   m0_inner_r, m0_inner_g, m0_inner_b;
    reg [7:0]   m0_outer_r, m0_outer_g, m0_outer_b;

    // ============================================================
    // 3. 数据转换映射 (组合逻辑，基于锁存后的输入)
    // ============================================================
    reg [23:0] g_rgb_flat [0:7];         // 存储 8 个灯泡的完整 24-bit GRB 数据

    // 解析四进制颜色编码映射 (0:灭, 1:绿, 2:红, 3:蓝)
    function [23:0] get_color;
        input [1:0] code;
        input [3:0] bright;
        reg [7:0] val;
        begin
            val = {bright, 4'b0000};     // 16档亮度 -> 8位色彩强度
            case(code)
                2'd1:    get_color = {val,  8'd0,  8'd0}; // 绿
                2'd2:    get_color = {8'd0, val,   8'd0}; // 红
                2'd3:    get_color = {8'd0, 8'd0,  val }; // 蓝
                default: get_color = 24'd0;               // 灭
            endcase
        end
    endfunction

    // 组合逻辑：根据锁存后的 mode / brightness / data 生成 8 个灯的 GRB 数据
    integer i;
    always @(*) begin
        // ============================================================
        // Mode 0 颜色解码：按内群/外群独立计算颜色通道
        //   内群使用 inner_brightness，外群使用 outer_brightness
        // ============================================================
        // 内群颜色
        if (|data32_latched[2:0]) begin
            m0_inner_r = data32_latched[0] ? {inner_brightness_latched, 4'b0} : 8'd0;
            m0_inner_g = data32_latched[1] ? {inner_brightness_latched, 4'b0} : 8'd0;
            m0_inner_b = data32_latched[2] ? {inner_brightness_latched, 4'b0} : 8'd0;
        end else begin
            m0_inner_r = 8'd0;
            m0_inner_g = {inner_brightness_latched, 4'b0};
            m0_inner_b = 8'd0;
        end
        // 外群颜色
        if (|data32_latched[2:0]) begin
            m0_outer_r = data32_latched[0] ? {outer_brightness_latched, 4'b0} : 8'd0;
            m0_outer_g = data32_latched[1] ? {outer_brightness_latched, 4'b0} : 8'd0;
            m0_outer_b = data32_latched[2] ? {outer_brightness_latched, 4'b0} : 8'd0;
        end else begin
            m0_outer_r = 8'd0;
            m0_outer_g = {outer_brightness_latched, 4'b0};
            m0_outer_b = 8'd0;
        end

        if (mode_latched == 1'b0) begin
            // 模式0: 8位二进制流映射，按内/外群使用独立亮度
            // 外群 LED (1,4,5,8) ← g_rgb_flat[0],[3],[4],[7]
            g_rgb_flat[3] = data10_latched[7] ? {m0_outer_g, m0_outer_r, m0_outer_b} : 24'd0;
            g_rgb_flat[0] = data10_latched[4] ? {m0_outer_g, m0_outer_r, m0_outer_b} : 24'd0;
            g_rgb_flat[4] = data10_latched[3] ? {m0_outer_g, m0_outer_r, m0_outer_b} : 24'd0;
            g_rgb_flat[7] = data10_latched[0] ? {m0_outer_g, m0_outer_r, m0_outer_b} : 24'd0;
            // 内群 LED (2,3,6,7) ← g_rgb_flat[1],[2],[5],[6]
            g_rgb_flat[2] = data10_latched[6] ? {m0_inner_g, m0_inner_r, m0_inner_b} : 24'd0;
            g_rgb_flat[1] = data10_latched[5] ? {m0_inner_g, m0_inner_r, m0_inner_b} : 24'd0;
            g_rgb_flat[5] = data10_latched[2] ? {m0_inner_g, m0_inner_r, m0_inner_b} : 24'd0;
            g_rgb_flat[6] = data10_latched[1] ? {m0_inner_g, m0_inner_r, m0_inner_b} : 24'd0;
        end
        else begin
            // 模式1: 数码管四进制级联控色模式
            // data32 => {id3高, id3低, id2高, id2低}, data10 => {id1高, id1低, id0高, id0低}
            g_rgb_flat[0] = get_color(data32_latched[7:6], inner_brightness_latched); // id3 上灯
            g_rgb_flat[1] = get_color(data32_latched[5:4], inner_brightness_latched); // id3 下灯
            g_rgb_flat[2] = get_color(data32_latched[3:2], inner_brightness_latched); // id2 上灯
            g_rgb_flat[3] = get_color(data32_latched[1:0], inner_brightness_latched); // id2 下灯

            g_rgb_flat[4] = get_color(data10_latched[7:6], inner_brightness_latched); // id1 上灯
            g_rgb_flat[5] = get_color(data10_latched[5:4], inner_brightness_latched); // id1 下灯
            g_rgb_flat[6] = get_color(data10_latched[3:2], inner_brightness_latched); // id0 上灯
            g_rgb_flat[7] = get_color(data10_latched[1:0], inner_brightness_latched); // id0 下灯
        end
    end

    // ============================================================
    // 4. 状态机与发送计数器控制
    // ============================================================
    reg         state; 
    localparam  ST_DATA  = 1'b0;
    localparam  ST_RESET = 1'b1;

    reg [5:0]   clk_cnt;   // 单个比特内的时钟计数器 (0 ~ BIT_TOTAL)
    reg [4:0]   bit_cnt;   // 当前灯泡正在发送的比特索引 (0 ~ 23)
    reg [2:0]   led_idx;   // 当前指向的灯泡硬件编号 (0 ~ 7)
    reg [15:0]  rst_cnt;   // 复位延迟专用计数器

    // 当前正在发送的单 bit 状态值缓存
    wire        current_bit;
    assign      current_bit = g_rgb_flat[led_idx][5'd23 - bit_cnt]; // 高位先发

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state    <= ST_RESET;
            clk_cnt  <= 6'd0;
            bit_cnt  <= 5'd0;
            led_idx  <= 3'd0;
            rst_cnt  <= 16'd0;
            led_out  <= 1'b0;
            // 锁存寄存器清零
            mode_latched     <= 1'b0;
            inner_brightness_latched <= 4'd0;
            outer_brightness_latched <= 4'd0;
            data10_latched   <= 8'd0;
            data32_latched   <= 8'd0;
        end 
        else begin
            case (state)
                ST_DATA: begin
                    // 串行脉宽信号生成逻辑
                    if (current_bit == 1'b1)
                        led_out <= (clk_cnt <= T1H_MAX) ? 1'b1 : 1'b0;
                    else
                        led_out <= (clk_cnt <= T0H_MAX) ? 1'b1 : 1'b0;

                    // 计数与流控自增
                    if (clk_cnt < BIT_TOTAL) begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end 
                    else begin
                        clk_cnt <= 6'd0;
                        if (bit_cnt < 5'd23) begin
                            bit_cnt <= bit_cnt + 1'b1;
                        end 
                        else begin
                            bit_cnt <= 5'd0;
                            if (led_idx < 3'd7) begin
                                led_idx <= led_idx + 1'b1;
                            end 
                            else begin
                                // 8个灯泡（192 bit）全部发送完毕，切入 Reset 复位帧
                                led_idx <= 3'd0;
                                state   <= ST_RESET;
                            end
                        end
                    end
                end

                ST_RESET: begin
                    led_out <= 1'b0; // 复位期间输出绝对低电平
                    if (rst_cnt < RST_COUNT) begin
                        rst_cnt <= rst_cnt + 1'b1;
                    end 
                    else begin
                        rst_cnt <= 16'd0;
                        // ========== 关键：帧起始锁存输入 ==========
                        mode_latched     <= mode;
                        inner_brightness_latched <= inner_brightness;
                        outer_brightness_latched <= outer_brightness;
                        data10_latched   <= led_data_in10;
                        data32_latched   <= led_data_in32;
                        // ======================================
                        state   <= ST_DATA; // 开始传输下一帧数据
                    end
                end
            endcase
        end
    end

endmodule