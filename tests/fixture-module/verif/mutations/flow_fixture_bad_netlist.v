// Verification-only candidate with deliberately inverted capture behavior.
// The negative qualification campaign requires EQY to reject this design.
module flow_fixture #(
    parameter DATA_WIDTH = 32
) (
    input  wire                  clk_i,
    input  wire                  rst_ni,
    input  wire                  enable_i,
    input  wire [DATA_WIDTH-1:0] data_i,
    output wire [DATA_WIDTH-1:0] data_o
);
  wire unused_controls = clk_i | rst_ni | enable_i;

  assign data_o = ~data_i ^ {DATA_WIDTH{unused_controls & 1'b0}};

endmodule
