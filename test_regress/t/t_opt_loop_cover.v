// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

typedef struct packed {
  logic [11:0] len;
  logic [19:0] info;
} item_t;

module t;
  localparam int N = 3;
  // Too many iterations for the inner loops to be unrolled
  localparam int M = 70;

  item_t [M-1:0] data;
  logic [N-1:0][11:0] offs;
  logic [M-1:0][7:0] wts;
  logic [M-1:0][3:0] keep_q;
  logic [M-1:0] en;
  int stop_at;

  // Every element written in one nest, a later read within the element just written
  item_t [N-1:0][M-1:0] head;
  logic [N-1:0][M-1:0][11:0] len;
  logic [N-1:0][M-1:0][15:0] wt;
  logic [N-1:0] mask;
  logic [M-1:0][3:0] keep_d;
  always_comb begin
    keep_d = keep_q;
    mask = '0;
    head = '0;
    len = '0;
    wt = '0;
    for (int i = 0; i < N; i++) begin
      mask[i] = ^offs[i];
      for (int j = 0; j < M; j++) begin
        head[i][j] = data[j];
        len[i][j] = head[i][j].len + offs[i];
        keep_d[j] = head[i][j].len[3:0];
        wt[i][j] = {wts[j], 8'b0};
      end
    end
  end

  // Written in descending order
  function automatic logic [M-1:0][3:0] reverse_f(input logic [M-1:0][3:0] in);
    logic [M-1:0][3:0] ret;
    for (int i = 0; i < M; i++) ret[M-1-i] = in[i];
    return ret;
  endfunction
  logic [M-1:0][3:0] rev;
  always_comb rev = reverse_f(keep_q);

  // The default stays where the loop does not overwrite every bit before reading it
  logic [M-1:0][3:0] miss_last;
  logic [M-1:0][3:0] read_first;
  logic [M-1:0][3:0] cond_write;
  logic [M-1:0][3:0] broken;
  logic [2*M-1:0] gaps;
  always_comb begin
    miss_last = '1;
    for (int j = 0; j < M - 1; j++) miss_last[j] = keep_q[j];
  end
  always_comb begin
    read_first = {M{4'h3}};
    for (int j = 0; j < M; j++) read_first[j] = read_first[j] + keep_q[j];
  end
  always_comb begin
    cond_write = {M{4'h5}};
    for (int j = 0; j < M; j++) if (en[j]) cond_write[j] = keep_q[j];
  end
  always_comb begin
    broken = {M{4'h6}};
    for (int j = 0; j < M; j++) begin
      if (j == stop_at) break;
      broken[j] = keep_q[j];
    end
  end
  always_comb begin
    gaps = '1;
    for (int j = 0; j < M; j++) gaps[2*j] = en[j];
  end

  // Also removed: a later write within the element, conditions the same in every iteration,
  // a 64-bit loop variable
  logic [M-1:0][3:0] within2;
  logic [M-1:0][3:0] cond_true;
  logic [M-1:0][3:0] cond_false;
  logic [M-1:0][3:0] long_var;
  logic [M-1:0][3:0] unsigned_var;
  always_comb begin
    within2 = '0;
    for (int j = 0; j < M; j++) begin
      within2[j] = keep_q[j];
      within2[j][0] = 1'b1;
    end
  end
  always_comb begin
    cond_true = '0;
    for (int j = 0; j < M; j++) cond_true[(j < M) ? j : 0] = keep_q[j];
  end
  always_comb begin
    cond_false = '0;
    for (int j = 0; j < M; j++) cond_false[(j >= M) ? 0 : j] = keep_q[j];
  end
  always_comb begin
    long_var = '0;
    for (longint j = 0; j < 64'(M); j++) long_var[j] = keep_q[j];
  end

  always_comb begin
    unsigned_var = '0;
    for (int unsigned j = 0; j < M; j++) unsigned_var[j] = keep_q[j];
  end

  // Kept, though every bit may be written: what the check does not take
  int zero_off;
  int one_mul;
  bit flag;
  logic [M-1:0][3:0] shifted;
  logic [M-1:0][3:0] overrun;
  logic [M-1:0][3:0] var_off;
  logic [M-1:0][3:0] var_mul;
  logic [M-1:0][3:0] swapped;
  logic [M-1:0][3:0] cond_open;
  logic [M-1:0][3:0] cond_var;
  logic [M-1:0][3:0] cond_neq;
  logic [M-1:0][3:0] halves;
  logic [N-1:0][M-1:0][3:0] inner_off;
  logic [M-1:0][3:0] whole;
  logic [M-1:0] whole_par;
  logic [M-1:0][3:0] mirrored;
  logic [M-1:0][3:0] mirror_rd;
  logic [M-1:0][3:0] next_write;
  logic [M-1:0][3:0] skipped;
  logic [M-1:0][3:0] le_test;
  logic [M-1:0][3:0] not_test;
  logic [M-1:0][3:0] other_test;
  logic [M-1:0][3:0] by_two;
  logic [M-1:0][3:0] from_neg;
  logic [M-1:0][3:0] wide_var;
  logic [M-1:0][3:0] after_sel;
  logic [M-1:0][3:0] read_by;
  int lim_var;
  logic [M-1:0][3:0] cond_lim;
  logic [M-1:0][3:0] huge_bound;
  logic [M-1:0][3:0] chunk_over;
  logic [M-1:0][3:0] reader;
  always_comb begin
    shifted = '1;
    for (int j = 0; j < M - 1; j++) shifted[j+1] = keep_q[j];
  end
  always_comb begin
    overrun = '1;
    // verilator lint_off SELRANGE
    for (int j = 0; j < M + 1; j++) overrun[j] = keep_q[j%M];
    // verilator lint_on SELRANGE
  end
  always_comb begin
    var_off = '1;
    for (int j = 0; j < M; j++) var_off[j+zero_off] = keep_q[j];
  end
  always_comb begin
    var_mul = '1;
    for (int j = 0; j < M; j++) var_mul[j*one_mul] = keep_q[j];
  end
  always_comb begin
    swapped = '1;
    for (int j = 0; j < M; j++) swapped[j^1] = keep_q[j];
  end
  always_comb begin
    cond_open = '1;
    for (int j = 0; j < M; j++) cond_open[(j < 35) ? 2 * j : 2 * j - 69] = keep_q[j];
  end
  always_comb begin
    cond_var = '1;
    for (int j = 0; j < M; j++) cond_var[flag ? j : 0] = keep_q[j];
  end
  always_comb begin
    cond_neq = '1;
    for (int j = 0; j < M; j++) cond_neq[(j != 99) ? j : 0] = keep_q[j];
  end
  always_comb begin
    halves = '1;
    for (int j = 0; j < M; j++) halves[j[7:1]] = keep_q[j];
  end
  always_comb begin
    inner_off = '1;
    for (int i = 0; i < N; i++)
      for (int j = 0; j < M; j++) inner_off[i][j+zero_off] = keep_q[j];
  end
  always_comb begin
    whole = '1;
    for (int j = 0; j < M; j++) begin
      whole[j] = keep_q[j];
      whole_par[j] = ^whole;
    end
  end
  always_comb begin
    mirrored = '1;
    for (int j = 0; j < M; j++) begin
      mirrored[j] = keep_q[j];
      mirror_rd[j] = mirrored[M-1-j];
    end
  end
  always_comb begin
    next_write = '1;
    for (int j = 0; j < M; j++) begin
      next_write[j] = keep_q[j];
      // verilator lint_off SELRANGE
      next_write[j+1][0] = 1'b0;
      // verilator lint_on SELRANGE
    end
  end
  always_comb begin
    skipped = '1;
    for (int j = 0; j < M; j++) begin
      skipped[j] = keep_q[j];
      if (en[j]) j++;
    end
  end
  always_comb begin
    le_test = '1;
    for (int j = 0; j <= M - 1; j++) le_test[j] = keep_q[j];
  end
  always_comb begin
    not_test = '1;
    for (int j = 0; !j[6]; j++) not_test[j] = keep_q[j];
  end
  always_comb begin
    automatic int k = 0;
    automatic int j = 0;
    other_test = '1;
    while (k < M) begin
      other_test[k] = keep_q[k];
      k++;
      j++;
    end
  end
  always_comb begin
    by_two = '1;
    for (int j = 0; j < M; j += 2) by_two[j] = keep_q[j];
  end
  always_comb begin
    from_neg = '1;
    for (int j = -1; j < M - 1; j++) from_neg[j+1] = keep_q[j+1];
  end
  always_comb begin
    wide_var = '1;
    for (bit [99:0] w = 0; w < 100'(M); w++) wide_var[w] = keep_q[w];
  end
  always_comb begin
    after_sel = '1;
    after_sel[0] = 4'h9;
    for (int j = 1; j < M; j++) after_sel[j] = keep_q[j];
  end
  always_comb begin
    cond_lim = '1;
    for (int j = 0; j < M; j++) cond_lim[(j < lim_var) ? j : 0] = keep_q[j];
  end
  always_comb begin
    huge_bound = '1;
    for (longint unsigned j = 64'hc000_0000_0000_0000; j < 64'hc000_0000_0000_0001; j++) begin
      huge_bound[0] = keep_q[0];
    end
  end
  always_comb begin
    chunk_over = '1;
    // verilator lint_off SELRANGE
    for (int j = 0; j < M / 2 + 1; j++) chunk_over[2*j+:2] = {keep_q[2*j+1], keep_q[2*j]};
    // verilator lint_on SELRANGE
  end
  // Only the one read before the loop is kept
  always_comb begin
    read_by = '1;
    reader = read_by;
    for (int j = 0; j < M; j++) begin
      read_by[j] = keep_q[j];
      reader[j] = keep_q[j];
    end
  end

  // A call between the assignment and the loop, or in the loop, may read the variable
  logic [M-1:0][3:0] obs_data;
  logic [3:0] obs_before;
  logic [M-1:0][3:0] obs_in;
  logic [M-1:0][3:0] obs_last;
  function automatic logic [3:0] obs_first_f();
    return obs_data[0];
  endfunction
  function automatic logic [3:0] obs_last_f();
    return obs_in[M-1];
  endfunction
  task automatic fill_observed(input logic [3:0] val);
    obs_data = '1;
    obs_before = obs_first_f();
    for (int j = 0; j < M; j++) obs_data[j] = val;
    obs_in = '1;
    for (int j = 0; j < M; j++) begin
      obs_in[j] = val;
      obs_last[j] = obs_last_f();
    end
  endtask

  // A hierarchical reference reads the variable too, in the loop or before it
  logic [M-1:0][3:0] xref_in;
  logic [M-1:0][3:0] xref_before;
  logic [3:0] xref_seen;
  task automatic fill_xref();
    xref_in = '0;
    for (int j = 0; j < M; j++) xref_in[j] = t.xref_in[(j+1)%M] + 4'(j);
    xref_before = '0;
    xref_seen = t.xref_before[0];
    for (int j = 0; j < M; j++) xref_before[j] = 4'(j + 1);
  endtask

  // Loops without a counted form, not after a whole-variable assignment
  int count_first;
  int count_after;
  logic [3:0] marks;
  initial begin
    while (count_first < 3) count_first++;
  end
  always_comb begin
    automatic int n = 0;
    marks = '0;
    marks[0] = 1'b1;
    while (n < 3) n++;
    count_after = n;
  end

  // A write waiting in the loop
  logic [M-1:0][3:0] waited;
  initial begin
    #2;
    waited = '1;
    for (int j = 0; j < M; j++) waited[j] = #1 keep_q[j];
  end

  initial begin
    zero_off = 0;
    lim_var = M;
    one_mul = 1;
    flag = 1'b1;
    for (int j = 0; j < M; j++) begin
      data[j] = {12'(j * 37 + 5), 20'(j * 1001)};
      wts[j] = 8'(j * 3);
      keep_q[j] = 4'(j * 7);
      en[j] = j[0];
    end
    for (int i = 0; i < N; i++) offs[i] = 12'(i * 100 + 7);
    stop_at = 50;
    #1;
    for (int i = 0; i < N; i++) begin
      `checkh(mask[i], ^offs[i]);
      for (int j = 0; j < M; j++) begin
        `checkh(head[i][j], data[j]);
        `checkh(len[i][j], data[j].len + offs[i]);
        `checkh(wt[i][j], {wts[j], 8'b0});
      end
    end
    for (int j = 0; j < M; j++) begin
      `checkh(keep_d[j], data[j].len[3:0]);
      `checkh(rev[M-1-j], keep_q[j]);
      `checkh(miss_last[j], j == M - 1 ? 4'hf : keep_q[j]);
      `checkh(read_first[j], 4'h3 + keep_q[j]);
      `checkh(cond_write[j], en[j] ? keep_q[j] : 4'h5);
      `checkh(broken[j], j < stop_at ? keep_q[j] : 4'h6);
      `checkh(gaps[2*j], en[j]);
      `checkh(gaps[2*j+1], 1'b1);
      `checkh(within2[j], keep_q[j] | 4'h1);
      `checkh(cond_true[j], keep_q[j]);
      `checkh(cond_false[j], keep_q[j]);
      `checkh(long_var[j], keep_q[j]);
      `checkh(unsigned_var[j], keep_q[j]);
      `checkh(shifted[j], j == 0 ? 4'hf : keep_q[j-1]);
      `checkh(overrun[j], keep_q[j]);
      `checkh(var_off[j], keep_q[j]);
      `checkh(var_mul[j], keep_q[j]);
      `checkh(swapped[j], keep_q[j^1]);
      `checkh(cond_open[j], j[0] ? keep_q[(j + 69) / 2] : keep_q[j/2]);
      `checkh(cond_var[j], keep_q[j]);
      `checkh(cond_neq[j], keep_q[j]);
      `checkh(halves[j], j < M / 2 ? keep_q[2*j+1] : 4'hf);
      for (int i = 0; i < N; i++) `checkh(inner_off[i][j], keep_q[j]);
      `checkh(whole[j], keep_q[j]);
      `checkh(mirror_rd[j], j > M - 1 - j ? keep_q[M-1-j] : 4'hf);
      `checkh(next_write[j], keep_q[j]);
      `checkh(le_test[j], keep_q[j]);
      `checkh(not_test[j], j < 64 ? keep_q[j] : 4'hf);
      `checkh(other_test[j], keep_q[j]);
      `checkh(by_two[j], j[0] ? 4'hf : keep_q[j]);
      `checkh(from_neg[j], keep_q[j]);
      `checkh(wide_var[j], keep_q[j]);
      `checkh(after_sel[j], j == 0 ? 4'h9 : keep_q[j]);
      `checkh(read_by[j], keep_q[j]);
      `checkh(cond_lim[j], keep_q[j]);
      `checkh(huge_bound[j], j == 0 ? keep_q[0] : 4'hf);
      `checkh(chunk_over[j], keep_q[j]);
      `checkh(reader[j], keep_q[j]);
    end
    begin
      automatic int j = 0;
      while (j < M) begin
        `checkh(skipped[j], keep_q[j]);
        if (en[j]) begin
          if (j + 1 < M) `checkh(skipped[j+1], 4'hf);
          j++;
        end
        j++;
      end
    end
    `checkh(count_first, 3);
    `checkh(count_after, 3);
    `checkh(marks, 4'h1);
    xref_in = '1;
    xref_before = '1;
    fill_xref();
    for (int j = 0; j < M; j++) begin
      `checkh(xref_in[j], 4'(j));
      `checkh(xref_before[j], 4'(j + 1));
    end
    `checkh(xref_seen, 4'h0);
    fill_observed(4'h0);
    `checkh(obs_before, 4'hf);
    for (int j = 0; j < M; j++) begin
      `checkh(obs_data[j], 4'h0);
      `checkh(obs_last[j], j == M - 1 ? 4'h0 : 4'hf);
    end
    #(M + 5);
    for (int j = 0; j < M; j++) `checkh(waited[j], keep_q[j]);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
