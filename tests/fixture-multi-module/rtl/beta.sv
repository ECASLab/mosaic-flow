module beta #(
    parameter int unsigned WIDTH = 2
) (
    input  logic [WIDTH-1:0] data_i,
    output logic [WIDTH-1:0] data_o
);

  assign data_o = ~data_i;

endmodule
