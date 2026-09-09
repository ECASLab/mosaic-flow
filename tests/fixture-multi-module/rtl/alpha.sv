module alpha #(
    parameter int unsigned WIDTH = 4
) (
    input  logic [WIDTH-1:0] data_i,
    output logic [WIDTH-1:0] data_o
);

    assign data_o = data_i;

endmodule
