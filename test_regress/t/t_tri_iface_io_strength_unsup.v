// DESCRIPTION: Verilator: Preserve the asymmetric interface I/O boundary
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

interface port_strength (
    inout wire value
);
  timeunit 1ns; timeprecision 1ps;
  bit ea = 0;
  bit eb = 0;
  bit a = 0;
  bit b = 1;
  assign (weak0, pull1) value = ea ? a : 1'bz;
  assign (pull0, pull1) value = eb ? b : 1'bz;
endinterface

interface output_strength (
    input bit data,
    output wire value
);
  assign (weak0, strong1) value = data;
  assign (pull0, pull1) value = 1'b1;
endinterface

module t;
  timeunit 1ns; timeprecision 1ps;
  wire value;
  port_strength io (value);
  bit data = 0;
  wire output_value;
  output_strength output_io (
      data,
      output_value
  );
  initial begin
    io.ea = 1;
    io.eb = 1;
    #1ns;
    if (value !== 1'b1) $fatal(1, "pull1 must dominate weak0 on interface port");
    $finish;
  end
endmodule
