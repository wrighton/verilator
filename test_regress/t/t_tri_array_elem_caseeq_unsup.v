// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t (
    input clk
);

  typedef struct {logic [7:0] f;} s_t;

  logic [7:0] mem[2];
  s_t s;
  logic [7:0] plain;

  always @(posedge clk) begin
    // A z written to an element or member is stored as two-state
    mem[0] <= 'z;
    s.f <= 'z;
    plain <= 8'h5a;
  end

  always @(posedge clk) begin
    if (mem[0] !== 8'bz) $stop;  // BAD: would read back two-state
    if (s.f === 8'bz) $stop;  // BAD: would read back two-state
    if (plain === 8'bz) $stop;  // Never z
  end

endmodule
