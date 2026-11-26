// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module leaf (
    input tri1 a,
    output logic isz,
    output logic val,
    output logic bval
);
  tri1 b;
  assign b = a;
  assign isz = (a === 1'bz);
  assign val = a;
  assign bval = b;
endmodule

// With a default of z, connected or not
module leafz (
    input tri1 a = 1'bz,
    output logic isz,
    output logic val
);
  assign isz = (a === 1'bz);
  assign val = a;
endmodule

module t;
  localparam realtime STEP = 1ns;
  // Pulled nets with a driver, or without one, never read as z
  logic d;
  logic isz;
  logic val;
  logic bval;
  leaf u (
      .a(d),
      .isz,
      .val,
      .bval
  );
  logic [2:0] zisz;
  logic [2:0] zval;
  leafz u_z0 (
      .a(d),
      .isz(zisz[0]),
      .val(zval[0])
  );
  leafz u_z1 (
      .isz(zisz[1]),
      .val(zval[1])
  );
  leafz u_z2 (
      .a(~d),
      .isz(zisz[2]),
      .val(zval[2])
  );
  tri0 n0;
  tri1 n1;
  tri hb;
  assign hb = u.b;
  initial begin
    for (int i = 0; i < 4; ++i) begin
      d = i[0];
      #STEP;
      `checkh(isz, 1'b0);
      `checkh(val, d);
      `checkh(bval, d);
      `checkh(u.b === 1'bz, 1'b0);
      `checkh(hb, d);
      `checkh(zisz, 3'b000);
      `checkh(zval, {~d, 1'b1, d});
      `checkh(n0 === 1'bz, 1'b0);
      `checkh(n1 === 1'bz, 1'b0);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
