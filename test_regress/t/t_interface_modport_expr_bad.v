// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Leela Pakanati
// SPDX-License-Identifier: CC0-1.0

interface iface;
  logic a, b;
  // Dotted path to non-existent signal
  modport mp1(input .in(nonexist.sig));
  // Complex expression not supported as modport expression
  modport mp2(input .in(~a));
endinterface

interface iface_inner;
  logic v;
endinterface

interface iface_port (
    iface_inner ip
);
  // Dotted path through interface port to non-existent signal
  modport mp3(input .in(ip.nonexist));
endinterface

module t;
  iface intf ();
  iface_inner inner ();
  iface_port intf_port (inner);
endmodule
