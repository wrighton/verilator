// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv, expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Sequence 'and' and 'intersect' with operands of variable length pair the matches of the
// operands of each attempt (IEEE 1800-2023 16.9.5, 16.9.6). A cover counts an attempt once, on
// its first match, and an assertion passes on its first match and fails once no match remains
// possible (16.14.1).

module t (
    input clk
);
  localparam int NCYC = 400;
  localparam int LOOKAHEAD = 64;
  localparam int NPROP = 16;

  integer cyc = 0;
  reg [63:0] crc = 64'h2f1e_8d3c_4b5a_6970;

  wire a = crc[0] | crc[11];
  wire b = crc[7] | crc[19];
  wire c = crc[13] | crc[3];
  wire d = crc[21] | crc[27];
  wire e = crc[33] | crc[41];

  bit ha[NCYC + LOOKAHEAD];
  bit hb[NCYC + LOOKAHEAD];
  bit hc[NCYC + LOOKAHEAD];
  bit hd[NCYC + LOOKAHEAD];
  bit he[NCYC + LOOKAHEAD];
  always @(posedge clk) begin
    ha[cyc] = a;
    hb[cyc] = b;
    hc[cyc] = c;
    hd[cyc] = d;
    he[cyc] = e;
  end

  int passes[NPROP];
  int fails[NPROP];
  int overLimitCovers = 0;

  // verilog_format: off
  cover property (@(posedge clk) (a [* 1:2]) and (b [* 2])) ++passes[0];
  assert property (@(posedge clk) (a [* 1:2]) and (b [* 2])) ++passes[1];
  else ++fails[1];
  cover property (@(posedge clk) (a ##[1:2] b) intersect (c [* 2:3])) ++passes[2];
  cover property (@(posedge clk) (a [* 1:3]) and (b ##[0:1] c)) ++passes[3];
  assert property (@(posedge clk) (a [* 1:3]) and (b ##[0:1] c)) ++passes[4];
  else ++fails[4];
  cover property (@(posedge clk) ((a [* 1:2]) and (b [* 2])) ##1 c) ++passes[5];
  // Nested 'and' and 'intersect' of fixed length
  cover property (@(posedge clk) ((a and b) ##1 c) and (d [* 2])) ++passes[6];
  cover property (@(posedge clk) ((a intersect b) ##1 c) and (d [* 2])) ++passes[7];
  assert property (@(posedge clk) (1'b1 ##[1:2] b) and (c ##1 d)) ++passes[8];
  else ++fails[8];
  assert property (@(posedge clk) (c ##1 d) and (1'b1 ##[1:2] b)) ++passes[9];
  else ++fails[9];
  // A wide delay range
  cover property (@(posedge clk) (a ##[1:60] (b && c && d)) and (c [* 2])) ++passes[10];
  // 'intersect' of operands of variable length with internal structure
  assert property (@(posedge clk) (a ##[1:3] b ##[1:2] c) intersect (d ##2 e)) ++passes[11];
  else ++fails[11];
  assert property (@(posedge clk) (a ##[1:3] (b ##1 c)) intersect (d ##[2:4] e)) ++passes[12];
  else ++fails[12];
  assert property (@(posedge clk) (a ##2 (b ##[1:3] c)) intersect (d ##[3:5] e)) ++passes[13];
  else ++fails[13];
  // Sequence 'or' operands
  cover property (@(posedge clk) ((a ##1 b) or (c ##2 d)) and (e [* 1:2])) ++passes[14];
  cover property (@(posedge clk) ((a or b) ##1 c) and (d [* 1:2])) ++passes[15];
  // Too long to lower per attempt
  cover property (@(posedge clk) (a [* 1:300]) and (b [* 2])) ++overLimitCovers;
  // verilog_format: on

  localparam int PASS = 1;
  localparam int FAIL = 2;
  localparam int NONE = 3;

  // The first tick of a run of a from s, of 1 to n iterations, or -1
  function automatic int first_rep_a(int s);
    return ha[s] ? s : -1;
  endfunction

  // The tick the last thread of (a [* 1:n]) ends on
  function automatic int rep_a_end(int s, int n);
    for (int k = 0; k < n; ++k) begin
      if (!ha[s+k]) return s + k;
    end
    return s + n - 1;
  endfunction

  // The first match tick of (b ##[0:1] c) from s, or -1, and the tick its last thread ends
  function automatic int bc_first(int s);
    if (!hb[s]) return -1;
    if (hc[s]) return s;
    return hc[s+1] ? s + 1 : -1;
  endfunction
  function automatic int bc_end(int s);
    return hb[s] ? s + 1 : s;
  endfunction

  // Outcome of the attempt of property i started on tick s, and the tick it resolves on
  task automatic expect_attempt(int i, int s, output int outcome, output int tick);
    bit a0 = ha[s], b0 = hb[s], c0 = hc[s], d0 = hd[s];
    bit a1 = ha[s+1], b1 = hb[s+1], c1 = hc[s+1], d1 = hd[s+1];
    bit a2 = ha[s+2], b2 = hb[s+2], c2 = hc[s+2];
    tick = s;
    outcome = NONE;
    case (i)
      0: begin
        tick = s + 1;
        if (a0 && b0 && b1) outcome = PASS;
      end
      1: begin
        if (!a0 || !b0) outcome = FAIL;
        else begin
          tick = s + 1;
          outcome = b1 ? PASS : FAIL;
        end
      end
      2: begin
        if (a0 && b1 && c0 && c1) begin
          tick = s + 1;
          outcome = PASS;
        end
        else if (a0 && b2 && c0 && c1 && c2) begin
          tick = s + 2;
          outcome = PASS;
        end
      end
      3, 4: begin
        int lhs = first_rep_a(s);
        int rhs = bc_first(s);
        if (lhs >= 0 && rhs >= 0) begin
          tick = lhs > rhs ? lhs : rhs;
          outcome = PASS;
        end
        else if (i == 4) begin
          // The first operand to have no match left fails the attempt
          int lhsEnd = lhs < 0 ? rep_a_end(s, 3) : NCYC + LOOKAHEAD;
          int rhsEnd = rhs < 0 ? bc_end(s) : NCYC + LOOKAHEAD;
          tick = lhsEnd < rhsEnd ? lhsEnd : rhsEnd;
          outcome = FAIL;
        end
      end
      5: begin
        tick = s + 2;
        if (a0 && b0 && b1 && c2) outcome = PASS;
      end
      6, 7: begin
        tick = s + 1;
        if (a0 && b0 && d0 && c1 && d1) outcome = PASS;
      end
      8, 9: begin
        // (c ##1 d) fails or matches on s+1, (1 ##[1:2] b) matches on s+1 or s+2
        if (!c0) outcome = FAIL;
        else if (!d1) begin
          tick = s + 1;
          outcome = FAIL;
        end
        else begin
          tick = b1 ? s + 1 : s + 2;
          outcome = b1 || b2 ? PASS : FAIL;
        end
      end
      11: begin
        // Only the shortest first operand has the length of the second one
        if (!a0 || !d0) outcome = FAIL;
        else begin
          tick = s + 2;
          outcome = b1 && c2 && he[s+2] ? PASS : FAIL;
        end
      end
      12: begin
        // The first operand ends on s+2 to s+4, its last thread after b on s+3
        if (!a0 || !d0) outcome = FAIL;
        else begin
          outcome = FAIL;
          tick = hb[s+3] ? s + 4 : s + 3;
          for (int t = s + 4; t >= s + 2; --t) begin
            if (hb[t-1] && hc[t] && he[t]) begin
              tick = t;
              outcome = PASS;
            end
          end
        end
      end
      13: begin
        if (!a0 || !d0) outcome = FAIL;
        else if (!b2) begin
          tick = s + 2;
          outcome = FAIL;
        end
        else begin
          outcome = FAIL;
          tick = s + 5;
          for (int t = s + 5; t >= s + 3; --t) begin
            if (hc[t] && he[t]) begin
              tick = t;
              outcome = PASS;
            end
          end
        end
      end
      14: begin
        // The 'or' first matches on s+1 or s+2, after e [* 1:2] first matches on s
        if (he[s]) begin
          if (a0 && b1) begin
            tick = s + 1;
            outcome = PASS;
          end
          else if (c0 && hd[s+2]) begin
            tick = s + 2;
            outcome = PASS;
          end
        end
      end
      15: begin
        tick = s + 1;
        if ((a0 || b0) && c1 && d0) outcome = PASS;
      end
      default: begin
        if (a0 && c0 && c1) begin
          for (int k = 1; k <= 60; ++k) begin
            if (hb[s+k] && hc[s+k] && hd[s+k]) begin
              tick = s + k;
              outcome = PASS;
              break;
            end
          end
        end
      end
    endcase
  endtask

  // Check the actions of the attempts resolving by tick last
  task automatic check_actions(int last);
    for (int i = 0; i < NPROP; ++i) begin
      int expPasses = 0;
      int expFails = 0;
      for (int s = 0; s <= last; ++s) begin
        int outcome;
        int tick;
        expect_attempt(i, s, outcome, tick);
        if (tick > last) continue;
        if (outcome == FAIL) ++expFails;
        else if (outcome == PASS) ++expPasses;
      end
      `checkd(passes[i], expPasses);
      `checkd(fails[i], expFails);
    end
  endtask

  always @(posedge clk) begin
    cyc <= cyc + 1;
    crc <= {crc[62:0], crc[63] ^ crc[2] ^ crc[0]};
  end

  always @(negedge clk) begin
    if (cyc == NCYC) begin
      check_actions(NCYC - 1);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
