// =================================================================
// 湖南大学 CSEE EC C301 - 综合选题3
// 文件功能：多通道换色效果发生器 V3.0
//           支持 5-Byte 协议 + 生命体征心跳呼吸灯
// =================================================================

module effect_generator (
    input               clk,             // 50MHz 系统时钟
    input               nrst,            // 低电平有效复位

    // 来自上层解析器的控制总线输入 (V3: 5-Byte Protocol)
    input       [7:0]   ctrl_mode,       // Byte 1: 控制模式 (0x01/0x02/0x03)
    input       [7:0]   ctrl_color,      // Byte 2: 全局颜色 (0x01=R, 0x02=G, 0x03=B)
    input       [7:0]   ctrl_brightness, // Byte 3: 全局亮度 (0x00~0xFF)
    input       [7:0]   ctrl_param,      // Byte 4: LED掩码 / 速度 / 节拍

    // 输出给底层驱动（你的 my_ws2812）的标准总线接口
    output reg  [7:0]   led_data_in10,   // 交付给驱动的 data10
    output reg  [7:0]   led_data_in32,   // 交付给驱动的 data32
    output reg          driver_mode,     // 驱动的双模式控制线 (0/1)
    output reg  [3:0]   inner_brightness,// 内群亮度 (LED 2,3,6,7) 4-bit
    output reg  [3:0]   outer_brightness,// 外群亮度 (LED 1,4,5,8) 4-bit

    // V4: Board 2 独立数据输出 (S型追逐双板驱动)
    output reg  [7:0]   led_data_in10_b2,// Board 2 低组数据
    output reg  [7:0]   led_data_in32_b2 // Board 2 高组数据
);

    //---------------------------------------------------------
    // 1. 内部定时基准发生器（50MHz时钟分频）
    //---------------------------------------------------------
    reg [24:0]  anim_clk_cnt;
    reg         step_pulse;              // 动画步进脉冲基准 (50ms)

    always @(posedge clk or negedge nrst) begin
        if (!nrst) begin
            anim_clk_cnt <= 25'd0;
            step_pulse   <= 1'b0;
        end else if (anim_clk_cnt == 25'd2499999) begin // 50ms 基础步进周期
            anim_clk_cnt <= 25'd0;
            step_pulse   <= 1'b1;
        end else begin
            anim_clk_cnt <= anim_clk_cnt + 25'd1;
            step_pulse   <= 1'b0;
        end
    end

    //---------------------------------------------------------
    // 2. 颜色解码器 (组合逻辑，将全局颜色字节映射为 data32 位域)
    //    my_ws2812.v 映射: bit[0]=R, bit[1]=G, bit[2]=B
    //---------------------------------------------------------
    reg [7:0] color_data32;
    always @(*) begin
        case (ctrl_color)
            8'h01: color_data32 = 8'h01; // 纯红 (bit[0]=R)
            8'h02: color_data32 = 8'h02; // 纯绿 (bit[1]=G)
            8'h03: color_data32 = 8'h04; // 纯蓝 (bit[2]=B)
            default: color_data32 = 8'h02; // 默认绿色
        endcase
    end

    //---------------------------------------------------------
    // 3. 大环流水灯动画 — 双板联动 (Mode = 8'h02)
    //    V4 Refactor: App 端 Timer 持续流式发送 Byte 4 = 当前步索引(0~15),
    //    FPGA 仅做组合逻辑译码, 不再自主动画.
    //
    //    追逐路径 (16步 Grand Ring):
    //      Board 1 Row 1 (右→左): LED 1→2→3→4  (bit[4][5][6][7])
    //      Board 1 Row 2 (左→右): LED 5→6→7→8  (bit[3][2][1][0])
    //      → 桥接到 Board 2 →
    //      Board 2 Row 1 (左→右): LED 1→2→3→4  (bit[4][5][6][7])
    //      Board 2 Row 2 (右→左): LED 8→7→6→5  (bit[0][1][2][3])
    //      → 循环回 Board 1 Step 0
    //---------------------------------------------------------
    reg [7:0] water_data_b1;
    reg [7:0] water_data_b2;
    always @(*) begin
        case (ctrl_param[3:0])  // 仅低4位有效, App 保证 step ∈ [0,15]
            // ── Board 1: LED 1→2→3→4→5→6→7→8 ──
            4'd0:  begin water_data_b1 = 8'b0001_0000; water_data_b2 = 8'b0000_0000; end
            4'd1:  begin water_data_b1 = 8'b0010_0000; water_data_b2 = 8'b0000_0000; end
            4'd2:  begin water_data_b1 = 8'b0100_0000; water_data_b2 = 8'b0000_0000; end
            4'd3:  begin water_data_b1 = 8'b1000_0000; water_data_b2 = 8'b0000_0000; end
            4'd4:  begin water_data_b1 = 8'b0000_1000; water_data_b2 = 8'b0000_0000; end
            4'd5:  begin water_data_b1 = 8'b0000_0100; water_data_b2 = 8'b0000_0000; end
            4'd6:  begin water_data_b1 = 8'b0000_0010; water_data_b2 = 8'b0000_0000; end
            4'd7:  begin water_data_b1 = 8'b0000_0001; water_data_b2 = 8'b0000_0000; end
            // ── Board 2: LED 1→2→3→4→8→7→6→5 ──
            4'd8:  begin water_data_b1 = 8'b0000_0000; water_data_b2 = 8'b0001_0000; end
            4'd9:  begin water_data_b1 = 8'b0000_0000; water_data_b2 = 8'b0010_0000; end
            4'd10: begin water_data_b1 = 8'b0000_0000; water_data_b2 = 8'b0100_0000; end
            4'd11: begin water_data_b1 = 8'b0000_0000; water_data_b2 = 8'b1000_0000; end
            4'd12: begin water_data_b1 = 8'b0000_0000; water_data_b2 = 8'b0000_0001; end
            4'd13: begin water_data_b1 = 8'b0000_0000; water_data_b2 = 8'b0000_0010; end
            4'd14: begin water_data_b1 = 8'b0000_0000; water_data_b2 = 8'b0000_0100; end
            4'd15: begin water_data_b1 = 8'b0000_0000; water_data_b2 = 8'b0000_1000; end
            default: begin water_data_b1 = 8'b0000_0000; water_data_b2 = 8'b0000_0000; end
        endcase
    end

    //---------------------------------------------------------
    // 3.5 S型往返追逐动画引擎 (Mode = 8'h04)
    //    追逐路径 (16步):
    //      Step  0~ 3: Board 1 LED 4→3→2→1 (bit[7][6][5][4])
    //      Step  4~11: Board 2 LED 1→2→3→4→5→6→7→8 (bit[4][5][6][7][3][2][1][0])
    //      Step 12~15: Board 1 LED 8→7→6→5 (bit[0][1][2][3])
    //      → 循环回 Step 0
    //---------------------------------------------------------
    reg  [3:0]  chase_step;          // 追逐当前步 (0~15)
    reg  [7:0]  chase_speed_cnt;     // 速度分频计数器

    always @(posedge clk or negedge nrst) begin
        if (!nrst) begin
            chase_step      <= 4'd0;
            chase_speed_cnt <= 8'd0;
        end else if (step_pulse && (ctrl_mode == 8'h04)) begin
            // ctrl_param 作为速度衰减因子：值越小，追逐越快
            if (chase_speed_cnt >= ctrl_param) begin
                chase_speed_cnt <= 8'd0;
                chase_step      <= (chase_step == 4'd15) ? 4'd0 : chase_step + 4'd1;
            end else begin
                chase_speed_cnt <= chase_speed_cnt + 8'd1;
            end
        end
    end

    // 追逐步 → 双板一热码映射 (组合逻辑)
    reg [7:0] chase_data_b1;
    reg [7:0] chase_data_b2;
    always @(*) begin
        case (chase_step)
            // --- Board 1 段: LED 4→3→2→1 (bit[7][6][5][4]) ---
            4'd0:  begin chase_data_b1 = 8'b1000_0000; chase_data_b2 = 8'b0000_0000; end
            4'd1:  begin chase_data_b1 = 8'b0100_0000; chase_data_b2 = 8'b0000_0000; end
            4'd2:  begin chase_data_b1 = 8'b0010_0000; chase_data_b2 = 8'b0000_0000; end
            4'd3:  begin chase_data_b1 = 8'b0001_0000; chase_data_b2 = 8'b0000_0000; end
            // --- Board 2 段: LED 1→2→3→4→5→6→7→8 (bit[4][5][6][7][3][2][1][0]) ---
            4'd4:  begin chase_data_b1 = 8'b0000_0000; chase_data_b2 = 8'b0001_0000; end
            4'd5:  begin chase_data_b1 = 8'b0000_0000; chase_data_b2 = 8'b0010_0000; end
            4'd6:  begin chase_data_b1 = 8'b0000_0000; chase_data_b2 = 8'b0100_0000; end
            4'd7:  begin chase_data_b1 = 8'b0000_0000; chase_data_b2 = 8'b1000_0000; end
            4'd8:  begin chase_data_b1 = 8'b0000_0000; chase_data_b2 = 8'b0000_1000; end
            4'd9:  begin chase_data_b1 = 8'b0000_0000; chase_data_b2 = 8'b0000_0100; end
            4'd10: begin chase_data_b1 = 8'b0000_0000; chase_data_b2 = 8'b0000_0010; end
            4'd11: begin chase_data_b1 = 8'b0000_0000; chase_data_b2 = 8'b0000_0001; end
            // --- Board 1 段: LED 8→7→6→5 (bit[0][1][2][3]) ---
            4'd12: begin chase_data_b1 = 8'b0000_0001; chase_data_b2 = 8'b0000_0000; end
            4'd13: begin chase_data_b1 = 8'b0000_0010; chase_data_b2 = 8'b0000_0000; end
            4'd14: begin chase_data_b1 = 8'b0000_0100; chase_data_b2 = 8'b0000_0000; end
            4'd15: begin chase_data_b1 = 8'b0000_1000; chase_data_b2 = 8'b0000_0000; end
            // --- 安全默认 ---
            default: begin chase_data_b1 = 8'b0000_0000; chase_data_b2 = 8'b0000_0000; end
        endcase
    end

    //---------------------------------------------------------
    // 4. 生命体征心跳呼吸灯波形发生器 (Mode = 8'h03)
    //    —— 仿生人体心跳节律：收缩快速点亮 → 舒张缓慢衰减
    //    24-bit 相位累加器，高4位划为16个节段 (0~15)：
    //      Seg  0~ 2 (18%):  Systole  收缩期 — 亮度 2→15 快速攀升
    //      Seg  3    ( 6%):  Peak     峰顶期 — 亮度 15   Hold
    //      Seg  4~ 9 (38%):  Diastole 舒张期 — 亮度 15→ 2 缓慢衰减
    //      Seg 10~15 (38%):  Pause    间歇期 — 亮度  2   低亮等待
    //---------------------------------------------------------
    reg [23:0]  hb_phase_acc;       // 24-bit 相位累加器
    wire [3:0] hb_segment;          // 高4位 = 16节段编号
    reg  [3:0] hb_brightness;       // 呼吸灯当前亮度输出

    assign hb_segment = hb_phase_acc[23:20];

    always @(posedge clk or negedge nrst) begin
        if (!nrst) begin
            hb_phase_acc <= 24'd0;
        end else if (ctrl_mode == 8'h03) begin
            // 相位累加：步长 = ctrl_param + 1，值越小节奏越快
            hb_phase_acc <= hb_phase_acc + {16'd0, ctrl_param} + 24'd1;
        end else begin
            hb_phase_acc <= 24'd0;  // 非心跳模式时复位相位
        end
    end

    // 节段 → 亮度映射 (组合逻辑)
    always @(*) begin
        case (hb_segment)
            // Systole: 快速收缩 ramping (2→15, 3节段)
            4'd0:  hb_brightness = 4'd2;
            4'd1:  hb_brightness = 4'd7;
            4'd2:  hb_brightness = 4'd12;
            // Peak: 峰顶保持 (15)
            4'd3:  hb_brightness = 4'd15;
            // Diastole: 缓慢舒张衰减 (15→2, 6节段)
            4'd4:  hb_brightness = 4'd15;
            4'd5:  hb_brightness = 4'd13;
            4'd6:  hb_brightness = 4'd11;
            4'd7:  hb_brightness = 4'd9;
            4'd8:  hb_brightness = 4'd6;
            4'd9:  hb_brightness = 4'd3;
            // Pause: 间歇低亮等待 (2, 6节段)
            4'd10, 4'd11, 4'd12, 4'd13, 4'd14, 4'd15:
                    hb_brightness = 4'd2;
            default: hb_brightness = 4'd2;
        endcase
    end

    //---------------------------------------------------------
    // 5. 时序逻辑仲裁多路选择器（寄存器输出）
    //    Mode 0x01: 独立灯珠控制 — ctrl_param = LED 位掩码
    //    Mode 0x02: 流水灯 — ctrl_param = 速度阻尼因子
    //    Mode 0x03: 心跳呼吸 — ctrl_param = 节拍速度，亮度由波形发生器驱动
    //    Mode 0x04: S型往返追逐 — ctrl_param = 追逐速度, 双板独立输出
    //    default:   保持上一组寄存器值不变
    //---------------------------------------------------------
    always @(posedge clk or negedge nrst) begin
        if (!nrst) begin
            led_data_in10   <= 8'd0;
            led_data_in32   <= 8'd0;
            led_data_in10_b2<= 8'd0;
            led_data_in32_b2<= 8'd0;
            driver_mode     <= 1'b0;
            inner_brightness <= 4'd10;
            outer_brightness <= 4'd10;
        end else begin
            case (ctrl_mode)
                8'h01: begin
                    // 独立灯珠控制：全局颜色 + 手动亮度 + LED 掩码
                    //   Board 1 & Board 2 镜像显示，同步点亮相同灯珠
                    driver_mode     <= 1'b0;
                    led_data_in10   <= ctrl_param;          // LED 位掩码
                    led_data_in32   <= color_data32;        // 解码后的颜色位域
                    led_data_in10_b2<= ctrl_param;          // Board 2 镜像 Board 1
                    led_data_in32_b2<= color_data32;
                    inner_brightness <= ctrl_brightness[7:4];
                    outer_brightness <= ctrl_brightness[7:4];
                end

                8'h02: begin
                    // 大环流水灯：App 流式发送步索引, 双板独立一热码输出
                    //   ctrl_param[3:0] = 当前步索引 (0~15, App Timer 驱动)
                    //   Board 1 数据 → led_data_in10, Board 2 数据 → led_data_in10_b2
                    driver_mode     <= 1'b0;
                    led_data_in10   <= water_data_b1;       // Board 1 一热码
                    led_data_in32   <= color_data32;        // 解码后的颜色位域
                    led_data_in10_b2<= water_data_b2;       // Board 2 一热码
                    led_data_in32_b2<= color_data32;        // 全局颜色
                    inner_brightness <= ctrl_brightness[7:4];// 统一亮度 (高 nibble)
                    outer_brightness <= ctrl_brightness[7:4];
                end

                8'h03: begin
                    // 中心对称波浪呼吸灯：Byte 3 高/低 nibble 分拆内/外群亮度
                    driver_mode     <= 1'b0;
                    led_data_in10   <= 8'hFF;               // 全部 8 灯珠点亮
                    led_data_in32   <= color_data32;        // 解码后的颜色位域
                    led_data_in10_b2<= 8'd0;                // Board 2 全灭 (呼吸灯仅Board 1)
                    led_data_in32_b2<= 8'd0;
                    inner_brightness <= ctrl_brightness[7:4];
                    outer_brightness <= ctrl_brightness[3:0];
                end

                8'h04: begin
                    // S型往返追逐：双板独立一热码输出
                    //   ctrl_param = 追逐速度 (1~15, 值小越快)
                    //   Board 1 数据 → led_data_in10, Board 2 数据 → led_data_in10_b2
                    driver_mode     <= 1'b0;
                    led_data_in10   <= chase_data_b1;       // Board 1 一热码
                    led_data_in32   <= color_data32;        // 全局颜色
                    led_data_in10_b2<= chase_data_b2;       // Board 2 独立S型追逐数据
                    led_data_in32_b2<= color_data32;        // 全局颜色
                    inner_brightness <= ctrl_brightness[7:4];// 追逐光点统一亮度
                    outer_brightness <= ctrl_brightness[7:4];
                end

                // default: 保持上一组寄存器值不变
                default: ;
            endcase
        end
    end

endmodule
