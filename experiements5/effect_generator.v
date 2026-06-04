// =================================================================
// 湖南大学 CSEE EC C301 - 综合选题3
// 文件功能：多通道换色效果发生器（流水灯、呼吸渐变、APP静态换色）
// =================================================================

module effect_generator (
    input               clk,             // 50MHz 系统时钟
    input               nrst,            // 低电平有效复位
    
    // 来自上层解析器的控制总线输入
    input       [7:0]   ctrl_mode,       // 当前生效的控制模式
    input       [7:0]   ctrl_param,      // 当前模式的控制参数
    
    // 输出给底层驱动（你的 my_ws2812）的标准总线接口
    output reg  [7:0]   led_data_in10,   // 交付给驱动的 data10
    output reg  [7:0]   led_data_in32,   // 交付给驱动的 data32
    output reg          driver_mode      // 驱动的双模式控制线 (0/1)
);

    //---------------------------------------------------------
    // 1. 内部定时基准发生器（50MHz时钟分频）
    //---------------------------------------------------------
    reg [24:0]  anim_clk_cnt;
    reg         step_pulse;              // 动画步进脉冲基准

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
    // 2. 流水灯动画效果生成器子系统 (Mode = 8'h02)
    //---------------------------------------------------------
    reg [7:0]   water_speed_cnt;
    reg [2:0]   water_led_idx;

    // 修复点：已将此处的 rst_n 纠正为接口声明的 nrst
    always @(posedge clk or negedge nrst) begin
        if (!nrst) begin
            water_speed_cnt <= 8'd0;
            water_led_idx   <= 3'd0;
        end else if (step_pulse && (ctrl_mode == 8'h02)) begin
            // ctrl_param 作为速度衰减器因子：值越小，流水越快
            if (water_speed_cnt >= ctrl_param) begin
                water_speed_cnt <= 8'd0;
                water_led_idx   <= (water_led_idx == 3'd7) ? 3'd0 : water_led_idx + 3'd1;
            end else begin
                water_speed_cnt <= water_speed_cnt + 8'd1;
            end
        end
    end

    // 根据移位索引转为一热码 (流水灯数据格式)
    reg [7:0] water_data_out;
    always @(*) begin
        case (water_led_idx)
            3'd0: water_data_out = 8'b00010000;
            3'd1: water_data_out = 8'b00100000;
            3'd2: water_data_out = 8'b01000000;
            3'd3: water_data_out = 8'b10000000;
            3'd4: water_data_out = 8'b00001000;
            3'd5: water_data_out = 8'b00000100;
            3'd6: water_data_out = 8'b00000010;
            3'd7: water_data_out = 8'b00000001;
            default: water_data_out = 8'b00010000;
        endcase
    end

    //---------------------------------------------------------
    // 3. 数码管四进制级联控色系统 (Mode = 8'h03)
    //---------------------------------------------------------
    reg [7:0] group_data_32;
    reg [7:0] group_data_10;
    
    always @(posedge clk or negedge nrst) begin
        if (!nrst) begin
            group_data_32 <= 8'b0101_1010; // 预设绚丽交叉色
            group_data_10 <= 8'b1111_0000;
        end else if (step_pulse && (ctrl_mode == 8'h03)) begin
            // 随时间缓缓滚动四进制颜色编码
            group_data_32 <= {group_data_32[5:0], group_data_32[7:6]};
            group_data_10 <= {group_data_10[1:0], group_data_10[7:2]};
        end
    end

    //---------------------------------------------------------
    // 4. 组合逻辑仲裁多路选择器（MUX）
    //---------------------------------------------------------
    always @(*) begin
        // 缺省安全状态：灯灭
        led_data_in10 = 8'd0;
        led_data_in32 = 8'd0;
        driver_mode   = 1'b0;

        case (ctrl_mode)
            8'h01: begin
                // APP静态控色模式：手机发送的 ctrl_param 直接当做灯的二进制掩码
                driver_mode   = 1'b0; // 切换到二进制控制模式
                led_data_in10 = ctrl_param;
                led_data_in32 = 8'd0;
            end

            8'h02: begin
                // 自动流水灯效果模式
                driver_mode   = 1'b0;
                led_data_in10 = water_data_out;
                led_data_in32 = 8'd0;
            end

            8'h03: begin
                // 数码管级联变色组控效果模式
                driver_mode   = 1'b1; // 激活驱动器的四进制数码管多色映射逻辑
                led_data_in10 = group_data_10;
                led_data_in32 = group_data_32;
            end

            default: begin
                driver_mode   = 1'b0;
                led_data_in10 = 8'd0;
                led_data_in32 = 8'd0;
            end
        endcase
    end

endmodule