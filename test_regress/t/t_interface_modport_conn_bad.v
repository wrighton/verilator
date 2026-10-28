// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

interface bus;
  logic a;
  modport m(input a);
  modport s(output a);
endinterface

module sub (
    bus.m p
);
endmodule

module gen (
    interface.m g
);
endmodule

// Modport selected through an interface port of the parent
module mid (
    bus p_in
);
  sub u_ok3 (.p(p_in.m));
  sub u_bad7 (.p(p_in.s));
endmodule

module holder;
  bus i ();
endmodule

module t;
  bus i ();
  bus ia[2] ();
  bus ia2[2][2] ();
  holder u_h ();
  // Legal: same modport, or a modport on only one side
  sub u_ok1 (.p(i.m));
  sub u_ok2 (.p(i));
  // Bad: port and connection modports differ (IEEE 1800-2023 25.5)
  sub u_bad1 (.p(i.s));
  sub u_bad2 (i.s);
  sub u_bad3 (.p(ia[1].s));
  gen u_bad4 (.g(i.s));
  mid u_mid (.p_in(i));
  // Bad, through a hierarchical reference, and an element of a nested array
  sub u_bad8 (.p(u_h.i.s));
  sub u_bad9 (.p(ia2[0][1].s));
  // Bad, but not a modport connection, so reported later
  sub u_bad6 (.p(i.s.a));
  // Bad: no such port
  sub u_bad5 (
      .p(i),
      .nope(i.s)
  );
endmodule
