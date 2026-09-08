// Minimal unconstrained harness shared by proof and property-reachability tasks.
module flow_fixture_formal;
  localparam int unsigned DATA_WIDTH = 32;

  (* gclk   *)logic                  clk_i;
  (* anyseq *)logic                  rst_ni;
  (* anyseq *)logic                  enable_i;
  (* anyseq *)logic [DATA_WIDTH-1:0] data_i;
  logic [DATA_WIDTH-1:0] data_o;

  flow_fixture #(.DATA_WIDTH(DATA_WIDTH)) dut (.*);

  // Select one shared wrapper for each proof or reachability task. Keeping
  // directives out of this harness prevents formal-only copies from diverging.
`ifdef FORMAL_ASSERTIONS
  flow_fixture_bind #(.DATA_WIDTH(DATA_WIDTH)) i_flow_fixture_bind (.*);
`endif

`ifdef FORMAL_COVERAGE
  flow_fixture_coverage_bind #(.DATA_WIDTH(DATA_WIDTH)) i_flow_fixture_coverage_bind (.*);
`endif

endmodule
