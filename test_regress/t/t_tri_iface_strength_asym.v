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

interface legacy_inout (
    inout wire value
);
  bit data;
  assign (weak0, strong1) value = data;
endinterface

interface legacy_output (
    output wire value
);
  bit data;
  assign (weak0, strong1) value = data;
endinterface

interface asymmetric_packed;
  bit enable;
  bit [6:0] data;
  wire [101:7] value;
  assign (weak0, weak1) value = 95'h555555555555555555555555;
  assign (pull0, supply1) value[73:67] = enable ? data : 7'bz;
  assign (pull0, pull1) value[42:36] = 7'b0;
  modport drive(inout value);
endinterface

module packed_asym_driver (
    asymmetric_packed.drive p,
    input bit enable,
    input bit [6:0] data
);
  assign (strong0, strong1) p.value[73:67] = enable ? data : 7'bz;
  assign (strong0, weak1) p.value[42:36] = enable ? data : 7'bz;
endmodule

interface many_defaults;
  wire value;
  assign (weak0, weak1) value = 1'b0;
  modport drive(inout value);
endinterface

module many_driver #(
    parameter int N = 128
) (
    many_defaults.drive p,
    input bit enable,
    data,
    input bit [$clog2(N)-1:0] chosen
);
  for (genvar g = 0; g < N; ++g) begin
    assign (strong0, strong1) p.value = enable && chosen == $clog2(N)'(g) ? data : 1'bz;
  end
endmodule

// Macro expansion keeps independent drivers in one lexical context per specialization.
// verilog_format: off
`define FLAT_ONE(k) assign (strong0, strong1) p.value = enable && chosen == $clog2(N)'(k) ? data : 1'bz;
`define FLAT16(b) \
  `FLAT_ONE((b)+0) `FLAT_ONE((b)+1) `FLAT_ONE((b)+2) `FLAT_ONE((b)+3) \
  `FLAT_ONE((b)+4) `FLAT_ONE((b)+5) `FLAT_ONE((b)+6) `FLAT_ONE((b)+7) \
  `FLAT_ONE((b)+8) `FLAT_ONE((b)+9) `FLAT_ONE((b)+10) `FLAT_ONE((b)+11) \
  `FLAT_ONE((b)+12) `FLAT_ONE((b)+13) `FLAT_ONE((b)+14) `FLAT_ONE((b)+15)
`define FLAT128(b) \
  `FLAT16((b)+0) `FLAT16((b)+16) `FLAT16((b)+32) `FLAT16((b)+48) \
  `FLAT16((b)+64) `FLAT16((b)+80) `FLAT16((b)+96) `FLAT16((b)+112)
`define FLAT256(b) `FLAT128(b) `FLAT128((b)+128)
// verilog_format: on

module flat_driver #(
    parameter int N = 128
) (
    many_defaults.drive p,
    input bit enable,
    data,
    input bit [$clog2(N)-1:0] chosen
);
  if (N == 128) begin : flat128
    `FLAT128(0)
  end
  else begin : flat256
    `FLAT256(0)
  end
endmodule

`undef FLAT_ONE
`undef FLAT16
`undef FLAT128
`undef FLAT256

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
  wire legacy_i;
  wire legacy_o;
  legacy_inout old_i (legacy_i);
  legacy_output old_o (legacy_o);
  asymmetric_packed packed_case ();
  bit [6:0] packed_data;
  packed_asym_driver packed_driver (
      packed_case,
      second,
      packed_data
  );
  many_defaults count128 ();
  many_defaults count256 ();
  bit [6:0] chosen128;
  bit [7:0] chosen256;
  many_driver #(128) many128 (
      count128,
      second,
      first,
      chosen128
  );
  many_driver #(256) many256 (
      count256,
      second,
      first,
      chosen256
  );
  many_defaults flat_count128 ();
  many_defaults flat_count256 ();
  flat_driver #(128) flat128 (
      flat_count128,
      second,
      first,
      chosen128
  );
  flat_driver #(256) flat256 (
      flat_count256,
      second,
      first,
      chosen256
  );
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
    bit [101:7] expected_packed;
    for (int i = 0; i < 16; ++i) begin
      first = i[0];
      second = i[1];
      active.data = first;
      pull_cross.data = first;
      inverse_cross.data = first;
      only_local.data = first;
      with_inactive.data = first;
      old_i.data = first;
      old_o.data = first;
      chosen128 = 7'(i * 17);
      chosen256 = 8'(i * 17);
      packed_case.enable = first;
      packed_case.data = 7'(i * 29 + 3);
      packed_data = 7'(i * 17 + 11);
      expected_packed = 95'h555555555555555555555555;
      expected_packed[42:36] = 0;
      if (first) begin
        expected_packed[73:67] = packed_case.data;
        if (second) expected_packed[73:67] |= packed_data;
      end
      else if (second) begin
        expected_packed[73:67] = packed_data;
      end
      #1;
      `checkh(active.value, 1'b1);
      `checkh(pull_cross.value, 1'b1);
      `checkh(inverse_cross.value, 1'b0);
      `checkh(only_local.value, first);
      `checkh(with_inactive.value, first);
      `checkh(sole_a.value, first);
      `checkh(sole_b.value, second);
      `checkh(paired.value, first & second);
      `checkh(legacy_i, first);
      `checkh(legacy_o, first);
      `checkh(packed_case.value, expected_packed);
      `checkh(count128.value, second ? first : 1'b0);
      `checkh(count256.value, second ? first : 1'b0);
      `checkh(flat_count128.value, second ? first : 1'b0);
      `checkh(flat_count256.value, second ? first : 1'b0);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
