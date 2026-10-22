// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Hierarchical interface port actuals resolving through a generate block or an
// arrayed instance (IEEE 1800-2023 25.3)

interface ifc;
  logic [6:0] d;
  modport mp(output d);
  modport mc(input d);
endinterface

module prod (
    ifc.mp b
);
  assign b.d = 7'h15;
endmodule

module cons (
    ifc.mc b
);
endmodule

module sub;
  ifc loc ();
  prod p (.b(loc.mp));
endmodule

module t;
  for (genvar g = 0; g < 2; ++g) begin : gfor
    ifc loc ();
    prod p (.b(loc.mp));
    cons c_inner (.b(gfor[g].loc));  // BAD
  end
  if (1) begin : gif
    ifc loc ();
    prod p (.b(loc.mp));
  end
  sub u_arr[2] ();

  cons c_for (.b(gfor[1].loc));  // BAD
  cons c_for_mp (.b(gfor[1].loc.mc));  // BAD
  cons c_if (.b(gif.loc));  // BAD
  cons c_if_mp (.b(gif.loc.mc));  // BAD
  cons c_arr (.b(u_arr[1].loc));  // BAD
  cons c_arr_mp (.b(u_arr[1].loc.mc));  // BAD
endmodule
