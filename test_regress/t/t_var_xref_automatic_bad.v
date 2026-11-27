// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Hierarchical references to automatic variables from outside their scopes
// (IEEE 1800-2023 6.21). Paths from within through the enclosing scopes, as in
// t_var_init_static_automatic, refer to the variable of the current activation.

// Into another instance of the same module
module leaf (
    input int seed,
    output int result
);
  initial begin
    begin : frame
      automatic int payload;
      payload = seed;
      #1;
      result = $root.t.v.frame.payload;
    end
  end
endmodule

module other;
  int seen;
  initial begin
    #2;
    // From another module
    seen = t.ob.w;
  end
endmodule

module t;
  int r1, r2, r3, a, b;
  other u_other ();
  leaf u (
      29,
      a
  );
  leaf v (
      73,
      b
  );
  initial begin
    begin : ib
      automatic int w;
      w = 3;
      r1 = ib.w;  // Within its scope
      begin : inner
        r2 = ib.w;  // Within its scope, nested
      end
    end
    begin : ob
      automatic int w;
      w = 4;
    end
    begin : sib
      // From a sibling block
      r3 = ob.w;
    end
  end
endmodule
