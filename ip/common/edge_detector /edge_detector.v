// ================================================================
// edge_detector.v
// 通用边沿检测器，将输入电平信号转换为单时钟周期脉冲
// 
// 参数：
//   WIDTH       : 输入信号位宽（默认4）
//   EDGE_TYPE   : 边沿类型，"POSITIVE"（上升沿）、"NEGATIVE"（下降沿）、"BOTH"（双边沿）
//
// 输入：
//   clk         : 时钟
//   rst_n       : 异步复位低有效
//   sig_in      : 输入电平信号（通常来自寄存器）
//
// 输出：
//   pulse_out   : 单周期脉冲信号，位宽与输入相同
/*
edge_detector #(
    .WIDTH      (4),
    .EDGE_TYPE  ("POSITIVE")
) u_clear_pulse_gen (
    .clk        (S_AXI_ACLK),          // AXI 时钟
    .rst_n      (S_AXI_ARESETN),       // AXI 复位（低有效）
    .sig_in     (slv_reg0[3:0]),       // 来自 AXI 写寄存器的电平信号
    .pulse_out  (clear_pulse)          // 输出单周期脉冲
);
*/
// ================================================================

module edge_detector #(
    parameter integer WIDTH      = 4,
    parameter string  EDGE_TYPE  = "POSITIVE"   // "POSITIVE" | "NEGATIVE" | "BOTH"
)(
    input  wire               clk,
    input  wire               rst_n,
    input  wire [WIDTH-1:0]   sig_in,
    output wire [WIDTH-1:0]   pulse_out
);

    // 打一拍，存储输入信号上一周期的值
    reg [WIDTH-1:0] sig_d1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            sig_d1 <= {WIDTH{1'b0}};
        else
            sig_d1 <= sig_in;
    end

    // 根据边沿类型产生脉冲
    generate
        if (EDGE_TYPE == "POSITIVE") begin
            assign pulse_out = sig_in & ~sig_d1;    // 上升沿
        end else if (EDGE_TYPE == "NEGATIVE") begin
            assign pulse_out = ~sig_in & sig_d1;    // 下降沿
        end else if (EDGE_TYPE == "BOTH") begin
            assign pulse_out = sig_in ^ sig_d1;     // 双边沿（异或）
        end else begin
            // 默认上升沿
            assign pulse_out = sig_in & ~sig_d1;
        end
    endgenerate

endmodule
