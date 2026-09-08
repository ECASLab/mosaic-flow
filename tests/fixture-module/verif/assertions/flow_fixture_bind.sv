// Stable wrapper boundary for attaching the assertion checker to the DUT.
module flow_fixture_bind #(
    parameter int unsigned DATA_WIDTH = 32
) (
    input logic                  clk_i,
    input logic                  rst_ni,
    input logic                  enable_i,
    input logic [DATA_WIDTH-1:0] data_i,
    input logic [DATA_WIDTH-1:0] data_o
);

  flow_fixture_sva #(.DATA_WIDTH(DATA_WIDTH)) i_flow_fixture_sva (.*);

endmodule

`ifndef MOSAIC_FORMAL
// Formal harnesses instantiate this wrapper explicitly because the Yosys
// frontend does not reliably apply simulation-oriented bind statements.
bind flow_fixture flow_fixture_bind #(.DATA_WIDTH(DATA_WIDTH)) i_flow_fixture_bind (.*);
`endif
