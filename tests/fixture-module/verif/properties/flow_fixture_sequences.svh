// Interface-specific sequence vocabulary shared by assertions and coverage.
// This file intentionally has no include guard because each wrapper needs its
// own module-scoped declarations.
sequence enabled_operation_s; enable_i; endsequence

sequence disabled_operation_s; !enable_i; endsequence

sequence representative_data_s; enable_i && data_i == 32'h1234_5678; endsequence
