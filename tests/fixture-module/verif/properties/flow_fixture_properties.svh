// Included inside assertion and coverage module scopes. An include guard would
// incorrectly suppress declarations in the second wrapper within one compile.
`include "flow_fixture_sequences.svh"

property representative_output_p;
  (enable_i && data_i == 32'h1234_5678) ##1 data_o == 32'h1234_5678;
endproperty

property reset_clears_output_p;
  !rst_ni |-> data_o == '0;
endproperty

property output_updates_when_enabled_p;
  disable iff (!rst_ni) enable_i |=> data_o == $past(
      data_i
  );
endproperty

property output_holds_when_disabled_p;
  disable iff (!rst_ni) !enable_i |=> $stable(
      data_o
  );
endproperty
