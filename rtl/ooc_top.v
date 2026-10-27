// File: ooc_top.v
// A simple wrapper to facilitate an Out-of-Context run for the 'aes' module.
`timescale 1ns / 1ps

module ooc_top(
    // These ports are just placeholders and will not be synthesized
    // into physical I/O when running in OOC mode.
    input clk,
    input nreset,
    input data_v_i,
    input [127:0] data_i,
    input [127:0] key_i,
    output res_v_o,
    output [127:0] res_o
    );

    // Instantiate the module we want to analyze
    aes dut (
        .clk(clk),
        .nreset(nreset),
        .data_v_i(data_v_i),
        .data_i(data_i),
        .key_i(key_i),
        .res_v_o(res_v_o),
        .res_o(res_o)
    );

endmodule