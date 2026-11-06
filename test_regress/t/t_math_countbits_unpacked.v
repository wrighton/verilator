// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

class Scoreboard;
  bit halt_req[];
endclass

class Env;
  Scoreboard sb = new;
endclass

module t;
  typedef bit bits_t[];

  typedef struct {bit [1:0] e[2];} inner_t;

  typedef struct {
    bit [2:0] a;
    logic [4:0] b[2];
    bit c[$];
    inner_t d;
  } item_t;

  typedef struct packed {
    bit [2:0] p;
    bit [3:0] q;
  } packed_t;

  // Dynamic array of bits: empty, zero, single, multiple and all bits set, then deleted
  initial begin
    bits_t halt_req;
    `checkd($countones(halt_req), 0);
    `checkd($countbits(halt_req, '1), 0);
    `checkd($countbits(halt_req, '0), 0);
    `checkd($onehot(halt_req), 1'b0);
    `checkd($onehot0(halt_req), 1'b1);
    `checkd($isunknown(halt_req), 1'b0);
    halt_req = new[12];
    `checkd($countones(halt_req), 0);
    `checkd($countbits(halt_req, '0), 12);
    `checkd($onehot(halt_req), 1'b0);
    `checkd($onehot0(halt_req), 1'b1);
    halt_req[0] = 1;
    `checkd($countones(halt_req), 1);
    `checkd($onehot(halt_req), 1'b1);
    `checkd($onehot0(halt_req), 1'b1);
    halt_req[11] = 1;
    `checkd($countones(halt_req), 2);
    `checkd($countbits(halt_req, '0), 10);
    `checkd($onehot(halt_req), 1'b0);
    `checkd($onehot0(halt_req), 1'b0);
    foreach (halt_req[i]) halt_req[i] = 1;
    `checkd($countones(halt_req), 12);
    `checkd($countbits(halt_req, '0, '1), 12);
    halt_req.delete();
    `checkd($countones(halt_req), 0);
    `checkd($onehot0(halt_req), 1'b1);
  end

  // Fixed, nested and associative arrays with multi-bit elements, compared to per-element counts
  initial begin
    bit [63:0] crc;
    logic [6:0] fixed[3:1];
    bit [32:0] wide[0:1];
    bit [4:0] nested[2][$];
    int assoc[string];
    byte wild[*];
    bit ctrl;
    int exp_fixed;
    int exp_wide;
    int exp_nested;
    int exp_assoc;
    crc = 64'h5aef0c8d_d70a4497;
    fixed = '{default: '0};
    for (int cyc = 0; cyc < 20; ++cyc) begin
      crc = {crc[62:0], crc[63] ^ crc[2] ^ crc[0]};
      fixed[1 + cyc % 3] = crc[6:0];
      wide[cyc % 2] = crc[40:8];
      nested[cyc % 2].push_back(crc[20:16]);
      if (cyc % 5 == 4) void'(nested[0].pop_front());
      assoc[$sformatf("%0d", cyc % 7)] = crc[31:0];
      wild[cyc % 3] = crc[47:40];
      ctrl = crc[0];
      exp_fixed = 0;
      foreach (fixed[i]) exp_fixed += $countones(fixed[i]);
      exp_wide = 0;
      foreach (wide[i]) exp_wide += $countones(wide[i]);
      exp_nested = 0;
      foreach (nested[i, j]) exp_nested += $countones(nested[i][j]);
      exp_assoc = 0;
      foreach (assoc[i]) exp_assoc += $countones(assoc[i]);
      for (int i = 0; i < 3; ++i) if (wild.exists(i)) exp_assoc += $countones(wild[i]);
      `checkd($countones(fixed), exp_fixed);
      `checkd($countbits(fixed, '0), 21 - exp_fixed);
      `checkd($countbits(fixed, ctrl), ctrl ? exp_fixed : 21 - exp_fixed);
      `checkd($onehot(fixed), exp_fixed == 1);
      `checkd($onehot0(fixed), exp_fixed <= 1);
      `checkd($countones(wide), exp_wide);
      `checkd($countbits(wide, '0, '1), 66);
      `checkd($countones(nested), exp_nested);
      `checkd($countbits(nested, '0), 5 * (nested[0].size() + nested[1].size()) - exp_nested);
      `checkd($countones(assoc) + $countones(wild), exp_assoc);
    end
  end

  // Queue of 4-state elements
  initial begin
    logic [3:0] q[$];
    q.push_back(4'b1010);
    q.push_back(4'b0111);
    `checkd($countones(q), 5);
    `checkd($countbits(q, '0), 3);
    `checkd($countbits(q, 'x), 0);
    `checkd($countbits(q, '1, 'x), 5);
    `checkd($isunknown(q), 1'b0);
    q.delete(0);
    `checkd($countones(q), 3);
    `checkd($onehot(q), 1'b0);
  end

  // Unpacked structs and arrays of them
  initial begin
    item_t s;
    item_t sa[2];
    packed_t pq[$];
    s.b = '{default: '0};
    `checkd($countones(s), 0);
    `checkd($countbits(s, '0), 17);
    s.a = 3'b101;
    s.b[1] = 5'b11000;
    s.c.push_back(1);
    s.c.push_back(0);
    s.d.e[1] = 2'b10;
    `checkd($countones(s), 6);
    `checkd($countbits(s, '0), 13);
    `checkd($onehot(s), 1'b0);
    sa[0].b = '{default: '0};
    sa[1] = s;
    sa[0].c.push_back(1);
    `checkd($countones(sa), 7);
    `checkd($onehot0(sa), 1'b0);
    pq.push_back('{p: 3'b001, q: 4'b0000});
    `checkd($onehot(pq), 1'b1);
    pq.push_back('{p: 3'b110, q: 4'b1011});
    `checkd($countones(pq), 6);
    `checkd($countones(pq[1]), 5);
  end

  // Continuous assignments, with elements wider than 64 bits
  bit [64:0] req[3];
  int req_count;
  bit req_onehot0;
  assign req_count = $countones(req);
  always_comb req_onehot0 = $onehot0(req);
  initial begin
    #1;
    `checkd(req_count, 0);
    `checkd(req_onehot0, 1'b1);
    req[2] = {1'b1, 64'b0};
    #1;
    `checkd(req_count, 1);
    `checkd(req_onehot0, 1'b1);
    req[0] = '1;
    #1;
    `checkd(req_count, 66);
    `checkd(req_onehot0, 1'b0);
  end

  // Class member dynamic array in a wait condition, compared to a packed mask
  Env env = new;
  bit [31:0] plusArgIntfEn = 32'h0000_0fff;
  bit inval_in_progress = 1;
  initial begin
    env.sb.halt_req = new[12];
    fork
      begin
        #1 inval_in_progress = 0;
        foreach (env.sb.halt_req[i]) #1 env.sb.halt_req[i] = 1;
      end
    join_none
    wait (($countones(env.sb.halt_req) == $countones(plusArgIntfEn)) && !inval_in_progress);
    `checkd($time, 13);
    `checkd($countones(env.sb.halt_req), 12);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
