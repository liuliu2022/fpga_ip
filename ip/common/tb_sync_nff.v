`timescale 1ns / 1ps

module tb_sync_nff;

    // ==========================================
    // 参数定义 (Parameter Definitions)
    // ==========================================
    // 将位宽设为4，同步级数设为3，以验证模块的参数化设计
    parameter WIDTH       = 4;
    parameter STAGES      = 3;
    parameter RESET_VALUE = 4'b1010; // 测试非零复位值

    // ==========================================
    // 信号声明 (Signal Declarations)
    // ==========================================
    reg                  dst_clk;
    reg                  dst_rst_n;
    reg      [WIDTH-1:0] async_in;
    wire     [WIDTH-1:0] sync_out;

    // ==========================================
    // 模块实例化 (Device Under Test)
    // ==========================================
    sync_nff #(
        .WIDTH(WIDTH),
        .STAGES(STAGES),
        .RESET_VALUE(RESET_VALUE)
    ) uut (
        .dst_clk(dst_clk),
        .dst_rst_n(dst_rst_n),
        .async_in(async_in),
        .sync_out(sync_out)
    );

    // ==========================================
    // 时钟生成 (Clock Generation)
    // ==========================================
    // 生成周期为 10ns 的时钟 (100MHz)
    always #5 dst_clk = ~dst_clk;

    // ==========================================
    // 测试激励 (Test Stimulus)
    // ==========================================
    initial begin
        // 1. 初始化
        dst_clk   = 1'b0;
        dst_rst_n = 1'b0;
        async_in  = 4'b0000;

        // 2. 维持复位状态一段时间
        #27; 
        
        // 3. 释放复位 (同步释放)
        @(posedge dst_clk);
        #1 dst_rst_n = 1'b1;
        
        // 观察复位值能否正确保持
        #30;

        // 4. 模拟异步输入 (Asynchronous Inputs)
        // 注意：这里的延时使用非 10ns 整数倍的随机延时（如 #13, #24），
        // 故意让信号在 dst_clk 的跳变沿附近或非边缘时刻发生变化，模拟真实的 CDC 场景。
        
        #13 async_in = 4'b1111; // 第一次异步跳变
        
        #44 async_in = 4'b0101; // 第二次异步跳变
        
        #62 async_in = 4'b1100; // 第三次异步跳变
        
        #21 async_in = 4'b0011; // 第四次异步跳变

        // 等待足够长的时间让最后的数据同步到输出
        #(STAGES * 10 + 50);

        // 5. 结束仿真
        $display("Simulation completed successfully.");
        $finish;
    end

    // ==========================================
    // 波形导出 (Waveform Dumping)
    // ==========================================
    initial begin
        // 适用于 Icarus Verilog, Vivado 或其他通用仿真器
        $dumpfile("tb_sync_nff.vcd");
        $dumpvars(0, tb_sync_nff);
    end

endmodule
