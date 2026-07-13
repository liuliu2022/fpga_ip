`timescale 1ns / 1ps
// =======================================================
// fanout_dispatcher_generic
// -------------------------------------------------------
// 通用高扇出信号分发器：
// 将一份源数据(code + update脉冲)打拍后，克隆成
// NUM_OUTPUTS 份物理独立的寄存器，防止综合器合并，
// 便于布局布线器把每份克隆推到物理上分散的目的地附近。
//
// 适用场景：DSA码分发到多个RF Tile、全局控制信号扇出到
// 多个物理分散的下游模块等。
// =======================================================
module fanout_dispatcher_generic #(
    parameter integer DATA_WIDTH  = 5,
    parameter integer NUM_OUTPUTS = 8,
    parameter [DATA_WIDTH-1:0] RESET_VALUE = {DATA_WIDTH{1'b0}}
)(
    input  wire                             clk,
    input  wire                             rst_n,

    input  wire [DATA_WIDTH-1:0]            data_in,
    input  wire                             data_update,

    output wire [NUM_OUTPUTS*DATA_WIDTH-1:0] data_out,      // 打平输出，便于跨模块例化
    output wire [NUM_OUTPUTS-1:0]            data_out_update
);

    // =======================================================
    // Stage 1: 本地缓冲打拍 (吸收上游逻辑延迟)
    // =======================================================
    reg [DATA_WIDTH-1:0] code_stage1;
    reg                  update_stage1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            code_stage1   <= RESET_VALUE;
            update_stage1 <= 1'b0;
        end else begin
            code_stage1   <= data_in;
            update_stage1 <= data_update;
        end
    end

    // =======================================================
    // Stage 2: generate循环生成 N 份物理独立的克隆寄存器
    // 每份单独打 dont_touch，禁止综合器跨实例合并，
    // 让布局布线器可以把每份就近推到对应物理目的地
    // =======================================================
    genvar i;
    generate
        for (i = 0; i < NUM_OUTPUTS; i = i + 1) begin : gen_clone
            (* dont_touch = "true" *) reg [DATA_WIDTH-1:0] clone_code;
            (* dont_touch = "true" *) reg                  clone_update;

            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    clone_code   <= RESET_VALUE;
                    clone_update <= 1'b0;
                end else begin
                    clone_code   <= code_stage1;
                    clone_update <= update_stage1;
                end
            end

            assign data_out[(i+1)*DATA_WIDTH-1 -: DATA_WIDTH] = clone_code;
            assign data_out_update[i]                          = clone_update;
        end
    endgenerate

endmodule
