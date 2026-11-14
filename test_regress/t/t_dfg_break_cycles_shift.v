// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0x exp=%0x (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

// Wide carry chains with each bit computed from lower bits of the same vector, or
// array element. Cycle breaking must not trace a copy of the chain per bit, which
// made the generated code quadratic in the width. The chains are wider than the
// minimum width V3DfgBreakCycles traces in chunks. Chains in a cycle through an
// adder or a left shift by a variable amount must not be traced in chunks, as each
// chunk would re-trace all lower bits of their operands.

module t;

  bit clk = 1'b0;
  always #5 clk = ~clk;

  localparam int W = 383;

  logic [W-1:0] a = '0;
  logic [W-1:0] b = '0;
  wire [W-1:0] g = a & b;
  wire [W-1:0] p = a ^ b;

  function automatic logic [W-1:0] cyExp(logic [W-1:0] gen, logic [W-1:0] prop);
    cyExp[0] = 1'b0;
    for (int i = 1; i < W; ++i) cyExp[i] = gen[i-1] | (prop[i-1] & cyExp[i-1]);
  endfunction

  // Carry from the LSB up
  logic [W-1:0] cyUp;
  assign cyUp = {g[W-2:0] | (p[W-2:0] & cyUp[W-2:0]), 1'b0};

  // Carry from the LSB up, non-zero based range
  logic [W+4:5] cyOff;
  assign cyOff = {g[W-2:0] | (p[W-2:0] & cyOff[W+3:5]), 1'b0};

  // Carry from the LSB up in an array element
  logic [W-1:0] cyArray[2];
  assign cyArray[0] = {g[W-2:0] | (p[W-2:0] & cyArray[0][W-2:0]), 1'b0};
  assign cyArray[1] = g;

  // Adder chain through an alias
  logic [W-1:0] sum;
  wire [W-1:0] sumAlias = sum | g;
  assign sum = {sumAlias[W-2:0] + p[W-2:0], 1'b1};

  function automatic logic [W-1:0] sumExp(logic [W-1:0] gen, logic [W-1:0] prop);
    logic carry = 1'b0;
    sumExp[0] = 1'b1;
    for (int i = 0; i < W - 1; ++i) begin
      sumExp[i+1] = (sumExp[i] | gen[i]) ^ prop[i] ^ carry;
      carry = ((sumExp[i] | gen[i]) & prop[i]) | (((sumExp[i] | gen[i]) ^ prop[i]) & carry);
    end
  endfunction

  // Adder through an alias, also shifted directly
  logic [W-1:0] mix;
  wire [W-1:0] mixAlias = mix ^ g;
  assign mix = {mixAlias[W-2:0] + p[W-2:0], 1'b0} ^ {mix[W-3:0], 2'b01};

  function automatic logic [W-1:0] mixExp(logic [W-1:0] gen, logic [W-1:0] prop);
    logic carry = 1'b0;
    mixExp[0] = 1'b1;
    for (int i = 1; i < W; ++i) begin
      mixExp[i] = (mixExp[i-1] ^ gen[i-1]) ^ prop[i-1] ^ carry ^ (i >= 2 ? mixExp[i-2] : 1'b0);
      carry = ((mixExp[i-1] ^ gen[i-1]) & prop[i-1])
          | (((mixExp[i-1] ^ gen[i-1]) ^ prop[i-1]) & carry);
    end
  endfunction

  // Left shift by a variable amount through an alias, also shifted directly
  logic [W-1:0] vsh;
  wire [W-1:0] vshAlias = vsh ^ g;
  assign vsh = ({vshAlias[W-2:0], 1'b1} << a[2:0]) ^ {vsh[W-3:0], 2'b01};

  function automatic logic [W-1:0] vshExp(logic [W-1:0] gen, int amount);
    for (int i = 0; i < W; ++i) begin
      vshExp[i] = (i < amount) ? 1'b0 : (i == amount) ? 1'b1 : vshExp[i-amount-1] ^ gen[i-amount-1];
      vshExp[i] ^= (i >= 2) ? vshExp[i-2] : (i == 0);
    end
  endfunction

  int cyc = 0;
  logic [63:0] lfsr = 64'h1;

  always @(posedge clk) begin
    cyc <= cyc + 1;
    lfsr <= {lfsr[62:0], lfsr[63] ^ lfsr[62] ^ lfsr[60] ^ lfsr[59]};
    a <= W'({6{lfsr}} >> lfsr[5:0]);
    b <= ~W'({6{lfsr}} >> lfsr[11:6]);
    if (lfsr[12]) b <= ~a;
    `checkh(cyUp, cyExp(g, p));
    `checkh(cyOff, cyExp(g, p));
    `checkh(cyArray[0], cyExp(g, p));
    `checkh(cyArray[1], g);
    `checkh(sum, sumExp(g, p));
    `checkh(mix, mixExp(g, p));
    `checkh(vsh, vshExp(g, int'(a[2:0])));
    if (cyc == 100) begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end

endmodule
