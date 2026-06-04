module pro1(
    input   clk,       // 50MHz 主时钟
    input   rst_n,     // 硬件复位按键，低电平有效
    input   key,       // 模式切换按键
    output  led_out    // 连接至 WS2812 采集板引脚
);

    reg [3:0] led_brightness;
    reg [7:0] led_data_in10;
    reg [7:0] led_data_in32;
    wire      mode;

    // 按键同步/消抖链路
    reg key_sync1, key_sync2;
    always @(posedge clk) begin
        key_sync1 <= key;
        key_sync2 <= key_sync1;
    end
    assign mode = key_sync2;

    // 边缘变化检测逻辑
    reg mode_delay;
    wire mode_change;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n)
            mode_delay <= 1'b0;
        else
            mode_delay <= mode;
    end
    assign mode_change = (mode != mode_delay);

    // 1Hz (1秒) 定时使能发生器控制
    reg [25:0] cnt;
    reg clk_en;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            cnt <= 26'd0;
            clk_en <= 1'b0;
        end
        else if(cnt == 26'd49999999) begin
            cnt <= 26'd0;
            clk_en <= 1'd1;
        end
        else begin
            cnt <= cnt + 1'b1;
            clk_en <= 1'd0;
        end
    end

    // 模式0：流水灯计数器
    reg [2:0] led_cnt;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            led_cnt <= 3'd0;
        end
        else if(mode_change) begin
            led_cnt <= 3'd0;
        end
        else if(clk_en && (mode == 1'd0)) begin
            led_cnt <= (led_cnt == 3'd7) ? 3'd0 : led_cnt + 1'd1;
        end
    end

    // 模式1：组控彩灯切换状态控制
    reg [1:0] color_sel;
    reg [1:0] group_sel;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            color_sel <= 2'd1;
            group_sel <= 2'd0;
        end
        else if(mode_change) begin
            color_sel <= 2'd1;
            group_sel <= 2'd0;
        end
        else if(clk_en && (mode == 1'b1)) begin
            color_sel <= (color_sel == 2'd3) ? 2'd1 : color_sel + 1'b1;
            group_sel <= (group_sel == 2'd3) ? 2'd0 : group_sel + 1'b1;
        end
    end

    // 组合逻辑：动态数据输出赋值转换
    always @(*) begin
        led_data_in10 = 8'd0;
        led_data_in32 = 8'd0;

        if(mode == 1'b0) begin
            // 模式 0: 流水灯映射
            case(led_cnt)
                3'd0: led_data_in10 = 8'b00010000;
                3'd1: led_data_in10 = 8'b00100000;
                3'd2: led_data_in10 = 8'b01000000;
                3'd3: led_data_in10 = 8'b10000000;
                3'd4: led_data_in10 = 8'b00001000;
                3'd5: led_data_in10 = 8'b00000100;
                3'd6: led_data_in10 = 8'b00000010;
                3'd7: led_data_in10 = 8'b00000001;
            endcase
        end
        else begin
            // 模式 1: 数码管模式组控彩灯映射
            case(group_sel)
                2'd0: begin
                    led_data_in10 = {4'd0 , color_sel , color_sel};
                    led_data_in32 = 8'd0;
                end
                2'd1: begin
                    led_data_in10 = {color_sel, color_sel, 4'd0};
                    led_data_in32 = 8'd0;
                end
                2'd2: begin
                    led_data_in32 = {4'd0, color_sel, color_sel};
                    led_data_in10 = 8'd0;
                end
                2'd3: begin
                    led_data_in32 = {color_sel, color_sel, 4'd0};
                    led_data_in10 = 8'd0;
                end
            endcase
        end
    end

    // 固定的全局默认亮度档位控制 (默认初始化在第 8 档)
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            led_brightness <= 4'd8;
        end
    end

    // 实例化底层的自定义模块：my_ws2812
    my_ws2812 u_my_ws2812 (
        .clk             (clk),
        .rst_n           (rst_n),
        .led_brightness  (led_brightness),
        .led_data_in10   (led_data_in10),
        .led_data_in32   (led_data_in32),
        .mode            (mode),
        .led_out         (led_out)
    );

endmodule