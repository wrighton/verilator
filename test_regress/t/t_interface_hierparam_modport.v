// DESCRIPTION: Verilator: Verilog Test module
//
// A hierarchical modport as an interface port actual of an instance reached
// by a hierarchical interface port actual.
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

interface bus_if #(
    parameter int W = 15
);
  logic [W-1:0] data;
  modport rd(input data);
endinterface

interface outer_if;
  bus_if b ();
endinterface

module relay (
    bus_if.rd src
);
  bus_if #(.W($bits(src.data))) out ();
endmodule

module holder;
  // Not the interface the modport is of
  bus_if #(.W(31)) b ();
  outer_if x ();
  relay r (.src(x.b.rd));
endmodule

module check_width (
    bus_if bus
);
  if ($bits(bus.data) != 15) begin : g_bad
    $error("Wrong interface parameters in generate condition");
  end
endmodule

module t;
  check_width c (.bus(h.r.out));
  holder h ();
endmodule
