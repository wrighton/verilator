// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module sub (
    inout wire [1:0] y
);
endmodule

module t;
  logic [1:0] v;
  int r;
  sub u_sub (.y(v));

  task automatic t_out(output logic [1:0] x);
    x = 2'b10;
  endtask
  task automatic t_inout(inout logic [1:0] x);
    x = ~x;
  endtask
  function automatic int f_output(output logic [1:0] x);
    x = 2'b10;
    return 3;
  endfunction
  function automatic int f_inout(inout logic [1:0] x);
    x = ~x;
    return 3;
  endfunction
  function automatic int f_ref(ref logic [1:0] x);
    x = ~x;
    return 3;
  endfunction

  initial begin
    v = 2'b01;
    t_inout(v);  // <--- Unsupported
    r = f_output(v);  // <--- Unsupported
    r = f_inout(v);  // <--- Unsupported
    r = f_ref(v);  // <--- Unsupported
    r = $sscanf("2", "%d", v);  // <--- Unsupported
    // Not in an assignment
    t_out(v);  // <--- Unsupported
    void'($sscanf("2", "%d", v));  // <--- Unsupported
  end
endmodule
