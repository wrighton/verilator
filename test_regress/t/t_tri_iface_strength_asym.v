// DESCRIPTION: Verilator: Per-driver asymmetric interface strengths
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got='h%x exp='h%x\n", `__FILE__, `__LINE__, (gotv), (expv)); `stop; end while (0);
// verilog_format: on

interface asymmetric;
  bit data;
  wire value;
  assign (weak0, strong1) value = data;
endinterface

interface inverse_asymmetric;
  bit data;
  wire value;
  assign (strong0, weak1) value = data;
endinterface

interface external_net;
  wire value;
  modport drive(inout value);
endinterface

module sole_driver (
    external_net.drive p,
    input bit data
);
  assign (weak0, strong1) p.value = data;
endmodule

module pair_driver (
    external_net.drive p,
    input bit first,
    second
);
  // Both statements have the same pair. They must split BEFORE their data is ORed.
  assign (strong0, weak1) p.value = first;
  assign (strong0, weak1) p.value = second;
endmodule

module t;
  // Retain the exact former Unsupported shape, now with an actual value oracle.
  asymmetric active ();
  assign active.value = 1'b1;
  asymmetric pull_cross ();
  assign (pull0, pull1) pull_cross.value = 1'b1;
  inverse_asymmetric inverse_cross ();
  assign (pull0, pull1) inverse_cross.value = 1'b0;
  asymmetric only_local ();
  asymmetric with_inactive ();
  assign (strong0, strong1) with_inactive.value = 1'bz;
  bit first = 0;
  bit second = 0;
  external_net sole_a ();
  external_net sole_b ();
  external_net paired ();
  sole_driver driver_a (
      sole_a,
      first
  );
  sole_driver driver_b (
      sole_b,
      second
  );
  pair_driver two_drivers (
      paired,
      first,
      second
  );

  initial begin
    for (int i = 0; i < 16; ++i) begin
      first = i[0];
      second = i[1];
      active.data = first;
      pull_cross.data = first;
      inverse_cross.data = first;
      only_local.data = first;
      with_inactive.data = first;
      #1;
      `checkh(active.value, 1'b1);
      `checkh(pull_cross.value, 1'b1);
      `checkh(inverse_cross.value, 1'b0);
      `checkh(only_local.value, first);
      `checkh(with_inactive.value, first);
      `checkh(sole_a.value, first);
      `checkh(sole_b.value, second);
      `checkh(paired.value, first & second);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
