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
  end
  if (1) begin : gif
    ifc loc ();
    prod p (.b(loc.mp));
  end
  sub u_arr[2] ();


  // Modport of an element of an interface array nested under an indexed prefix
  nest_if nn[2] ();
  for (genvar g = 0; g < 2; ++g) begin : gnest
    nest_if n ();
  end
  cons c_nn_mp (.b(nn[0].arr[1].mc));  // BAD
  cons c_gnest_mp (.b(gnest[1].n.arr[0].mc));  // BAD
  if (1) begin : gifn
    nest_if n ();
  end
  cons c_gifn_mp (.b(gifn.n.arr[0].mc));  // BAD
endmodule

interface nest_if;
  ifc arr[2] ();
endinterface
