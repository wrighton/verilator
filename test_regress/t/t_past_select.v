// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__, `__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Sampled value functions of selections, whose value before the first clock tick
// is the default sampled value of the selection (IEEE 1800-2023 16.5.1, 16.9.3)
module t (
    input clk
);

  int cyc = 0;
  // Not initialized in the declaration, so default sampled values are 0
  int cnt[7:4];
  bit [6:0] v;
  int m[2][1:3];
  struct {
    int a;
    bit [4:0] b;
  } st;
  // Initialized, but indexed by a variable whose default sampled value is unknown
  bit [3:0] lut[1:4] = '{4'd9, 4'd10, 4'd11, 4'd12};
  integer idx;
  // Initialized, so default sampled values are from the initial values
  struct {
    int a;
    bit [4:0] b;
  } sti = '{3, 5'h0a};
  int k = 2;
  // 4-state, so default sampled values are unknown
  logic [3:0] m4[4];
  logic [3:0] v4;
  logic [1:0] i4;
  // Every element nonzero, so an unknown index read as some index is not the default value 0
  localparam bit [3:0] ONES = 4'hf;
  bit [3:0] sevens[4] = '{default: 4'd7};
  logic [1:0] ix;

  initial begin
    cnt = '{1, 2, 3, 4};
    v = 7'h55;
    m = '{'{1, 2, 3}, '{4, 5, 6}};
    st.a = 7;
    st.b = 5'h1f;
    idx = 1;
    m4 = '{1, 2, 3, 4};
    v4 = 4'h5;
    i4 = 0;
    ix = 0;
  end

  int id;
  assign id = cyc % 4;

  always @(posedge clk) begin
    cyc <= cyc + 1;
    cnt[id+4] <= cnt[id+4] + 1;
    v <= v + 7'd3;
    m[cyc%2][id%3+1] <= m[cyc%2][id%3+1] + 2;
    st.b <= st.b - 5'd1;
    idx <= idx + 1;
    sti.b <= sti.b + 5'd3;
    k <= k % 4 + 1;
    if (cyc == 20) begin
      `checkd(stable_fails, 3);
      `checkd(past_fails, 1);
      `checkd(lut_fails, 0);
      `checkd(m4_fails, 0);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end

  int exp_cnt = 0;
  bit [2:0] exp_v = 0;
  int exp_m = 0;
  bit [2:0] exp_b = 0;
  bit [3:0] exp_lut = 0;
  bit [1:0] exp_sti = 2'b10;
  bit [3:0] exp_lutk = 4'd10;
  always @(posedge clk) begin
    `checkd($past(cnt[id+4]), exp_cnt);
    `checkd($past(v[id+:3]), exp_v);
    `checkd($past(m[cyc%2][id%3+1]), exp_m);
    `checkd($past(st.b[3:1]), exp_b);
    `checkd($past(lut[idx%4+1]), exp_lut);
    `checkd($past(sti.b[id+:2]), exp_sti);
    `checkd($past(lut[k]), exp_lutk);
    `checkd($stable(cnt[5]), cyc == 0 ? 0 : id != 2);
    `checkd($rose(v[3]), v[3] && !exp_v3);
    `checkd($fell(st.b[0]), !st.b[0] && exp_b0);
    `checkd($changed(st.a), cyc == 0);
    `checkd($past(ONES[ix]), cyc == 0 ? 1'b0 : 1'b1);
    `checkd($past(sevens[ix]), cyc == 0 ? 4'd0 : 4'd7);
    exp_cnt <= cnt[id+4];
    exp_v <= v[id+:3];
    exp_m <= m[cyc%2][id%3+1];
    exp_b <= st.b[3:1];
    exp_lut <= lut[idx%4+1];
    exp_sti <= sti.b[id+:2];
    exp_lutk <= lut[k];
  end
  bit exp_v3 = 0;
  bit exp_b0 = 0;
  always @(posedge clk) begin
    exp_v3 <= v[3];
    exp_b0 <= st.b[0];
  end

  // cnt[5] changes on cycles 1, 5, 9, ...; checked through cycle 19
  int stable_fails = 0;
  assert property (@(posedge clk) cyc == 0 || cyc > 12 || $stable(cnt[5]))
  else stable_fails++;

  // False only on the first tick, from the default sampled value
  int past_fails = 0;
  assert property (@(posedge clk) $past(cnt[id+4] > 0) && cnt[id+4] != 0)
  else past_fails++;

  int lut_fails = 0;
  assert property (@(posedge clk) int'($past(lut[idx%4+1])) == (cyc == 0 ? 0 : 9 + (idx + 3) % 4))
  else lut_fails++;

  // The unknown default sampled values only affect the first tick
  int m4_fails = 0;
  assert property (@(posedge clk) cyc == 0 || ($stable(m4[1]) && $stable(v4[i4]) && !$rose(m4[i4][0])))
  else m4_fails++;

endmodule
