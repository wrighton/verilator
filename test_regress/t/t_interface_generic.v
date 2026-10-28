// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2025 Antmicro
// SPDX-License-Identifier: CC0-1.0

interface ifc;
  int v;
endinterface

interface inf2;
  int k;
  modport mp(output k);
endinterface

module GenericModule (
    interface a,
    interface b
);
  initial begin
    #1;
    if (a.v != 7) $stop;
    b.k = 9;
  end
endmodule

module Wrapper (
    interface c,
    interface d
);
  GenericModule genericModule (
      c,
      d
  );
endmodule

module t;
  ifc inf_inst ();
  inf2 inf_inst2 ();
  GenericModule genericModule (
      inf_inst,
      inf_inst2
  );
  // Same interface types again, connected through a modport
  ifc inf_inst3 ();
  inf2 inf_inst4 ();
  GenericModule genericModule2 (
      inf_inst3,
      inf_inst4.mp
  );
  // Same interface types again, forwarded through generic ports
  ifc inf_inst5 ();
  inf2 inf_inst6 ();
  Wrapper wrapper (
      inf_inst5,
      inf_inst6
  );
  initial begin
    inf_inst.v = 7;
    inf_inst3.v = 7;
    inf_inst5.v = 7;
    #2;
    if (inf_inst2.k != 9) $stop;
    if (inf_inst4.k != 9) $stop;
    if (inf_inst6.k != 9) $stop;
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
