module profile_fixture #(
    parameter int unsigned WIDTH = 8,
    parameter bit FEATURE_INVERT = 1'b0
) (
    input  logic [WIDTH-1:0] data_i,
    output logic [WIDTH-1:0] data_o
);

  assign data_o = FEATURE_INVERT ? ~data_i : data_i;

endmodule
