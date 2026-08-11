module flow_fixture_sva #(
    parameter int unsigned DATA_WIDTH = 32
) (
    input logic                  clk_i,
    input logic                  rst_ni,
    input logic                  enable_i,
    input logic [DATA_WIDTH-1:0] data_i,
    input logic [DATA_WIDTH-1:0] data_o
);

  output_updates_when_enabled :
  assert property (@(posedge clk_i) disable iff (!rst_ni) enable_i |=> data_o == $past(data_i));

  output_holds_when_disabled :
  assert property (@(posedge clk_i) disable iff (!rst_ni) !enable_i |=> $stable(data_o));

endmodule
