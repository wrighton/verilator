// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module t (
    input clk
);

  typedef struct packed {
    logic [17:0] f0;
    logic signed [14:0] f1;  // Straddles a 32-bit word boundary
    logic [3:0][12:0] f2;
  } s_t;

  function automatic logic signed [14:0] calc(logic signed [14:0] v, logic [63:0] r);
    return ((v * $signed(r[22:8])) ^ (v + $signed(r[40:26]))) + (v >>> r[3:0])
        - $signed(r[63:49]) * 3 + ((v & $signed(r[14:0])) | (v ^ $signed(r[30:16])))
        * (v - 15'sd5);
  endfunction

  // Field update reading the field itself, with an expression too large to substitute
  function automatic s_t upd(s_t x, logic [63:0] r);
    s_t y;
    y = x;
    y.f1 = ((y.f1 * $signed(r[22:8])) ^ (y.f1 + $signed(r[40:26]))) + (y.f1 >>> r[3:0])
        - $signed(r[63:49]) * 3 + ((y.f1 & $signed(r[14:0])) | (y.f1 ^ $signed(r[30:16])))
        * (y.f1 - 15'sd5);
    y.f2[r[3:0]%4] = r[42:30];
    return y;
  endfunction

  s_t m = '0;
  logic signed [14:0] exp_f1 = '0;
  logic [63:0] crc = 64'h5aef0c8d_d70a4497;
  int cyc = 0;

  always @(posedge clk) begin
    cyc <= cyc + 1;
    crc <= {crc[62:0], crc[63] ^ crc[2] ^ crc[0]};
    m <= upd(m, crc);
    exp_f1 <= calc(exp_f1, crc);
    `checkh(m.f1, exp_f1);
    if (cyc == 99) begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
