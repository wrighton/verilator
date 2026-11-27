// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// A property with an 'and' of a sequence of unbounded length decides each attempt once, at its
// first match (IEEE 1800-2023 16.9.5, 16.14.1). The counts are checked against attempts
// enumerated from the sampled values.
module t (
    input clk
);
  localparam int CYCLES = 300;

  int cyc = 0;
  reg [63:0] crc = 64'h5aef_0c8d_d70a_4497;
  always @(posedge clk) begin
    cyc <= cyc + 1;
    crc <= {crc[62:0], crc[63] ^ crc[2] ^ crc[0]};
  end
  // Sparse: attempts do not overlap
  wire d = cyc % 8 < 2 || cyc % 16 == 2;
  wire f = cyc % 8 < 2;
  // Random
  wire a = crc[0] | crc[3];
  wire b = crc[5] | crc[9];
  wire c = crc[13] | crc[17];

  int sparse_n = 0, rand_n = 0, two_n = 0, imp_p = 0, imp_f = 0, ok_p = 0, ok_f = 0;
  cover property (@(posedge clk) (d [* 1:$]) and f) ++sparse_n;
  cover property (@(posedge clk) (a [* 1:$]) and b) ++rand_n;
  cover property (@(posedge clk) (a [+]) and (b ##2 c)) ++two_n;
  assert property (@(posedge clk) c |-> (a [* 2:$]) and (b ##1 a)) ++imp_p;
  else ++imp_f;
  // A repetition with a subroutine call keeps its lengths, as each repetition calls it
  function automatic void nop();
  endfunction
  // verilator lint_off SIDEEFFECT
  cover property (@(posedge clk) ((a, nop()) [* 1:$]) and b);
  // verilator lint_on SIDEEFFECT
  // A repetition followed by more keeps its lengths
  assert property (@(posedge clk) c |-> (a [* 1:2] ##1 b) and (1'b1 ##2 1'b1)) ++ok_p;
  else ++ok_f;

  bit ha[CYCLES], hb[CYCLES], hc[CYCLES], hd[CYCLES], hf[CYCLES];
  always @(posedge clk) begin
    if (cyc < CYCLES) begin
      ha[cyc] = a;
      hb[cyc] = b;
      hc[cyc] = c;
      hd[cyc] = d;
      hf[cyc] = f;
    end
  end

  always @(negedge clk) begin
    if (cyc == CYCLES) begin
      automatic int e_sparse = 0, e_rand = 0, e_two = 0, e_ip = 0, e_if = 0, e_op = 0, e_of = 0;
      // Attempts deciding before the last tick
      for (int s = 0; s < CYCLES; ++s) begin
        if (hd[s] && hf[s]) ++e_sparse;
        if (ha[s] && hb[s]) ++e_rand;
        if (s + 2 < CYCLES && ha[s] && hb[s] && hc[s+2]) ++e_two;
        // (a [*2:$]) and (b ##1 a): fails without a or b at the start, then decides a tick on
        if (!hc[s]) ++e_ip;
        else if (!ha[s] || !hb[s]) ++e_if;
        else if (s + 1 < CYCLES) begin
          if (ha[s+1]) ++e_ip;
          else ++e_if;
        end
        // (a [*1:2] ##1 b) and (1 ##2 1): a match two ticks on, through b on the next tick or
        // a then b
        if (!hc[s]) ++e_op;
        else if (!ha[s]) ++e_of;
        else if (s + 1 < CYCLES && !hb[s+1] && !ha[s+1]) ++e_of;
        else if (s + 2 < CYCLES) begin
          if (hb[s+1] || hb[s+2]) ++e_op;
          else ++e_of;
        end
      end
      `checkd(sparse_n, e_sparse);
      `checkd(rand_n, e_rand);
      `checkd(two_n, e_two);
      `checkd(imp_p, e_ip);
      `checkd(imp_f, e_if);
      `checkd(ok_p, e_op);
      `checkd(ok_f, e_of);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
