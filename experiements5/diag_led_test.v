// =================================================================
// 湖南大学 CSEE EC C301 - 综合选题3
// 文件功能：双板 WS2812 纯硬件诊断模块
//          绕过 UART/parser/effect 全部上层逻辑，
//          硬编码 8 灯全亮绿色，直接驱动两个 my_ws2812 实例。
//
// 使用方法：
//   1. 将 .qsf 中的 TOP_LEVEL_ENTITY 改为 diag_led_test
//   2. 编译、烧录
//   3. 观察两个板子是否都亮 8 个绿灯
//
// 结果解读：
//   - Board 1 亮 + Board 2 亮 → 硬件都正常，问题在 effect_generator 数据
//   - Board 1 亮 + Board 2 不亮 → Board 2 物理硬件损坏/接触不良/供电问题
//   - Board 1 不亮           → FPGA 基础时钟/复位异常
// =================================================================

module diag_led_test (
    input           clk,           // 50MHz 主时钟 (PIN_E1)
    input           rst_n,         // 硬件复位 (PIN_L2)
    output          led_out,       // Board 1 数据输出 (PIN_T3)
    output          led_out_b2     // Board 2 数据输出 (PIN_T2)
);

    // ── 硬编码测试数据 ──
    //    8'hFF: 所有 8 路 LED 点亮 (bit[7:0] 各对应 1 灯)
    //    8'h02: 绿色 (bit[1]=G, bit[0]=R, bit[2]=B)
    //    4'hF:  最大亮度 (高 nibble = 0xF → 0xF0 = 240/255 ≈ 94%)
    wire [7:0] test_data10 = 8'hFF;     // 全亮
    wire [7:0] test_data32 = 8'h02;     // 纯绿
    wire [3:0] test_bright  = 4'hF;     // 最高亮度
    wire       test_mode    = 1'b0;     // 二进制模式 (非四进制)

    // ── Board 1 驱动实例 (板载 8 灯) ──
    my_ws2812 u_diag_b1 (
        .clk                (clk),
        .rst_n              (rst_n),
        .inner_brightness   (test_bright),	
        .outer_brightness   (test_bright),
        .led_data_in10      (test_data10),
        .led_data_in32      (test_data32),
        .mode               (test_mode),
        .led_out            (led_out)
    );

    // ── Board 2 驱动实例 (外接 PMOD 8 灯) ──
    my_ws2812 u_diag_b2 (
        .clk                (clk),
        .rst_n              (rst_n),
        .inner_brightness   (test_bright),
        .outer_brightness   (test_bright),
        .led_data_in10      (test_data10),   // ⬅ 与 Board 1 完全相同的数据
        .led_data_in32      (test_data32),
        .mode               (test_mode),
        .led_out            (led_out_b2)
    );

endmodule
