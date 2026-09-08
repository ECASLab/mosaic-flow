// Shared functional checker used by simulation, PyUVM, and formal verification.
module flow_fixture_sva #(
    parameter int unsigned DATA_WIDTH = 32
) (
    input logic                  clk_i,
    input logic                  rst_ni,
    input logic                  enable_i,
    input logic [DATA_WIDTH-1:0] data_i,
    input logic [DATA_WIDTH-1:0] data_o
);

`ifdef MOSAIC_YOSYS_FORMAL
  // Yosys cannot parse the concurrent SVA library. This procedural form keeps
  // the same reset, update, and hold semantics in the shared checker wrapper.
  logic past_valid = 1'b0;

  always_ff @(posedge clk_i) begin
    past_valid <= 1'b1;

    if (!rst_ni) begin
      assert (data_o == '0);
    end else if (past_valid && $past(rst_ni)) begin
      if ($past(enable_i)) begin
        assert (data_o == $past(data_i));
      end else begin
        assert (data_o == $past(data_o));
      end
    end
  end
`else
  // Simulation and SVA-capable formal tools consume the common properties.
  `include "flow_fixture_properties.svh"

reset_clears_output :
  assert property (@(posedge clk_i) reset_clears_output_p);

  output_updates_when_enabled :
  assert property (@(posedge clk_i) output_updates_when_enabled_p);

  output_holds_when_disabled :
  assert property (@(posedge clk_i) output_holds_when_disabled_p);
`endif

endmodule
