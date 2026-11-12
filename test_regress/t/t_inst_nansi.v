// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2025 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t (
    b,
    si,
    i,
    li,
    w3,
    w4,
    sp,
    sn,
    sop,
    son
);
  output b;  // Output before type
  output si;
  byte b;
  shortint si;

  int i;
  longint li;
  output i;  // Output after type
  output li;

  input [2:0] w3;
  wire [2:0] w3;
  wire [3:0] w4;
  input [3:0] w4;

  // Signed on either declaration applies to both (IEEE 1800-2023 23.2.2.1)
  input signed [7:0] sp;  // Signed I/O before type
  wire [7:0] sp;
  wire signed [7:0] sn;  // Signed type before I/O
  input [7:0] sn;
  logic [7:0] sop;  // Type before signed I/O
  output signed [7:0] sop;
  output [7:0] son;  // I/O before signed type
  logic signed [7:0] son;

  initial begin
    if ($typename(sp) != "logic signed[7:0]") $stop;
    if ($typename(sn) != "logic signed[7:0]") $stop;
    if ($typename(sop) != "logic signed[7:0]") $stop;
    if ($typename(son) != "logic signed[7:0]") $stop;
  end

  initial begin
    if ($bits(b) != 8) $stop;
    if ($bits(si) != 16) $stop;
    if ($bits(i) != 32) $stop;
    if ($bits(li) != 64) $stop;
    if ($bits(w3) != 3) $stop;
    if ($bits(w4) != 4) $stop;
    $finish;
  end

endmodule
