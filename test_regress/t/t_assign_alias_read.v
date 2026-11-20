// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module t;
  bit clk = 0;
  always #5 clk = ~clk;

  // A clocked block reads a copy of 'v' through a function, then writes 'v'. It gets 'v'
  // from before the write.
  typedef bit [7:0][7:0] w_t;
  int n = 0;
  w_t v;
  w_t d;
  w_t alias_v;
  assign alias_v = v;
  function automatic w_t copy(w_t w);
    w_t r;
    for (int i = 0; i < 8; i++) r[i] = w[i];
    return r;
  endfunction
  always @(posedge clk) begin
    d = copy(alias_v);
    n++;
    for (int i = 0; i < 8; i++) v[i] = 8'(n + i);
  end

  // The same with a single byte
  int sn = 0;
  bit [6:0] sv;
  bit [6:0] sd;
  bit [6:0] alias_sv;
  assign alias_sv = sv;
  function automatic bit [6:0] scopy(bit [6:0] w);
    return w;
  endfunction
  always @(posedge clk) begin
    sd = scopy(alias_sv);
    sn++;
    sv = 7'(sn);
  end

  // The same with the inverse of 'iv'
  int in = 0;
  bit [6:0] iv;
  bit [6:0] id;
  bit [6:0] inv_iv;
  assign inv_iv = ~iv;
  always @(posedge clk) begin
    id = scopy(inv_iv);
    in++;
    iv = 7'(in);
  end

  // A clocked block reads a copy of 'nv', and writes 'nv' with a non-blocking assignment
  int nn = 0;
  bit [6:0] nv;
  bit [6:0] nd;
  bit [6:0] alias_nv;
  assign alias_nv = ~nv;
  always @(posedge clk) begin
    nd <= alias_nv;
    nn <= nn + 1;
    nv <= 7'(nn);
  end

  // A clocked block reads a copy of 'wv', which a function called in a non-blocking
  // assignment writes. It gets 'wv' from before the write.
  bit [6:0] wv = 0;
  bit [6:0] wd;
  bit [6:0] alias_wv;
  int wsum = 0;
  int wones[1] = '{1};
  assign alias_wv = wv;
  function automatic int wbump(int i);
    wv = wv + 7'd1;
    return i;
  endfunction
  always @(posedge clk) begin
    wd <= alias_wv;
    wsum <= wsum + wones.sum() with (wbump(item));
  end

  // The same, with 'seed' written by $random in a non-blocking assignment
  int seed = 1;
  int rd;
  int rx;
  int alias_seed;
  int rprev;
  assign alias_seed = seed;
  function automatic int icopy(int w);
    return w;
  endfunction
  always @(posedge clk) begin
    rd <= icopy(alias_seed);
    rx <= $random(seed);
  end

  // A clocked block writes 'gv', then reads a copy of it in a function that is not inlined.
  // It gets 'gv' from before the write.
  bit [6:0] gv;
  bit [6:0] gd;
  bit [6:0] alias_gv;
  assign alias_gv = gv;
  function automatic bit [6:0] gread(bit descend);
    if (descend) return gread(1'b0);
    return alias_gv;
  endfunction
  always @(posedge clk) begin
    gv = gv + 7'd1;
    gd <= gread(gv[0]);
  end

  // A timed process reads the inverse of 'tsrc' after writing 'tsrc' on a clock edge. It gets
  // the inverse of 'tsrc' from before the write.
  bit [6:0] tsrc = 0;
  bit [6:0] tcap;
  bit [6:0] inv_tsrc;
  assign inv_tsrc = ~tsrc;
  always begin
    #1;
    @(posedge clk) begin
      tsrc = tsrc + 7'd1;
      tcap = inv_tsrc;
    end
  end

  // A timed process waits for an edge of a copy of 'esrc' right after writing 'esrc'. It
  // waits from the value the copy had before the write.
  bit esrc = 0;
  bit ewoke = 0;
  bit ecopy;
  assign ecopy = esrc;
  always begin
    @(negedge clk);
    esrc = 1;
    @(posedge ecopy);
    ewoke = 1;
    @(negedge clk);
    esrc = 0;
  end

  // A copy of a signal written by a blocking assignment in clocked logic triggers a process
  bit div = 0;
  bit alias_div;
  int divn = 0;
  int divref = 0;
  assign alias_div = div;
  always @(posedge clk) div = ~div;
  always @(posedge alias_div) divn <= divn + 1;
  always @(posedge div) divref <= divref + 1;

  initial begin
    @(negedge clk);
    rprev = seed;
    repeat (4) begin
      @(negedge clk);
      `checkd(d[0], v[0] - 8'd1);
      `checkd(d[7], v[7] - 8'd1);
      `checkd(sd, sv - 7'd1);
      `checkd(id, ~7'(iv - 7'd1));
      `checkd(tcap, ~7'(tsrc - 7'd1));
      `checkd(nd, ~7'(nn - 2));
      `checkd(wd, wv - 7'd1);
      `checkd(rd, rprev);
      rprev = seed;
      `checkd(gd, gv - 7'd1);
      `checkd(divn, divref);
    end
    `checkd(ewoke, 1);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
