// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module opaque_forcer;
  import "DPI-C" function logic unrepresented_value();
  initial begin
    #2 force t.n = unrepresented_value();
  end
endmodule

module t;
  logic enabled = 1;
  wire n;
  assign n = enabled ? 1'b1 : 1'bz;
  opaque_forcer u ();
  initial begin
    #1 force n = 1'bz;
    #4 enabled = 0;
  end

  wire [6:0] source;
  assign source = enabled ? 7'h11 : 7'bz;
  wire selected;
  assign selected = enabled ? 1'b1 : 1'bz;
  int count = 0;
  function automatic int next_index();
    count = count + 1;
    return count % 7;
  endfunction
  initial #1 force selected = source[next_index()];
  initial #1 force selected = source[$urandom&1];
  function automatic int random_index();
    random_index = $urandom & 1;
  endfunction
  function automatic int nested_random_index();
    return random_index();
  endfunction
  initial #1 force selected = source[random_index()];
  initial #1 force selected = source[nested_random_index()];

  function automatic void set_z(output logic value);
    value = 1'bz;
  endfunction
  function automatic logic indirect_value();
    indirect_value = 1'b1;
    set_z(indirect_value);
  endfunction
  wire indirect;
  assign indirect = enabled ? 1'b1 : 1'bz;
  initial #1 force indirect = indirect_value();
endmodule
