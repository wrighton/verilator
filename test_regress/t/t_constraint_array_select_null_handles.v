// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Reads through rand and non-rand class handles, with each handle null in turn: an element
// of an array, by a random and a state index; a foreach over the array, at the top and under
// a random condition; a scalar member, as a value and as an index; a guard reading the last
// handle; and an element of a non-random array by a random index, read through a table. A
// read through a null handle is an evaluation error that fails randomize() (IEEE 1800-2023
// 18.5.12), as nothing is read through it.

class Leaf;
  rand bit [7:0] d[];
  bit [7:0] st[4];  // Read by a random index as a table of its values
  bit [7:0] k;
  function new();
    d = '{8'h11, 8'h12};
    st = '{8'h21, 8'h22, 8'h23, 8'h24};
    k = 1;
  endfunction
endclass

class Mid;
  rand Leaf rl;
  Leaf nl;
  function new();
    rl = new;
    nl = new;
  endfunction
endclass

class Top;
  rand Mid rm;
  Mid nm;
  function new();
    rm = new;
    nm = new;
  endfunction
endclass

class Paths;
  rand Mid m;  // Two handles on the path to the leaf
  rand Top t;  // Three
  rand int j;
  rand bit [7:0] y;
  rand bit [7:0] a[4];
  int unsigned s;
  int path;
  int kind;
  bit randIndex;
  constraint c {
    j inside {[0 : 1]};
    if (path == 0 && kind == 0 && randIndex) y == m.rl.d[j];
    if (path == 0 && kind == 0 && !randIndex) y == m.rl.d[s];
    if (path == 0 && kind == 1) foreach (m.rl.d[i]) y != m.rl.d[i];
    if (path == 0 && kind == 2 && y != 0) foreach (m.rl.d[i]) y != m.rl.d[i];
    if (path == 0 && kind == 3) y == m.rl.k;
    if (path == 0 && kind == 4) a[m.rl.k[1:0]] == 8'h5a;
    if (path == 0 && kind == 5) if (m.rl != null) y == m.rl.k;
    if (path == 0 && kind == 6) y == m.rl.st[j];
    if (path == 1 && kind == 0 && randIndex) y == m.nl.d[j];
    if (path == 1 && kind == 0 && !randIndex) y == m.nl.d[s];
    if (path == 1 && kind == 1) foreach (m.nl.d[i]) y != m.nl.d[i];
    if (path == 1 && kind == 2 && y != 0) foreach (m.nl.d[i]) y != m.nl.d[i];
    if (path == 1 && kind == 3) y == m.nl.k;
    if (path == 1 && kind == 4) a[m.nl.k[1:0]] == 8'h5a;
    if (path == 1 && kind == 5) if (m.nl != null) y == m.nl.k;
    if (path == 1 && kind == 6) y == m.nl.st[j];
    if (path == 2 && kind == 0 && randIndex) y == t.rm.rl.d[j];
    if (path == 2 && kind == 0 && !randIndex) y == t.rm.rl.d[s];
    if (path == 2 && kind == 1) foreach (t.rm.rl.d[i]) y != t.rm.rl.d[i];
    if (path == 2 && kind == 2 && y != 0) foreach (t.rm.rl.d[i]) y != t.rm.rl.d[i];
    if (path == 2 && kind == 3) y == t.rm.rl.k;
    if (path == 2 && kind == 4) a[t.rm.rl.k[1:0]] == 8'h5a;
    if (path == 2 && kind == 5) if (t.rm.rl != null) y == t.rm.rl.k;
    if (path == 2 && kind == 6) y == t.rm.rl.st[j];
    if (path == 3 && kind == 0 && randIndex) y == t.rm.nl.d[j];
    if (path == 3 && kind == 0 && !randIndex) y == t.rm.nl.d[s];
    if (path == 3 && kind == 1) foreach (t.rm.nl.d[i]) y != t.rm.nl.d[i];
    if (path == 3 && kind == 2 && y != 0) foreach (t.rm.nl.d[i]) y != t.rm.nl.d[i];
    if (path == 3 && kind == 3) y == t.rm.nl.k;
    if (path == 3 && kind == 4) a[t.rm.nl.k[1:0]] == 8'h5a;
    if (path == 3 && kind == 5) if (t.rm.nl != null) y == t.rm.nl.k;
    if (path == 3 && kind == 6) y == t.rm.nl.st[j];
    if (path == 4 && kind == 0 && randIndex) y == t.nm.rl.d[j];
    if (path == 4 && kind == 0 && !randIndex) y == t.nm.rl.d[s];
    if (path == 4 && kind == 1) foreach (t.nm.rl.d[i]) y != t.nm.rl.d[i];
    if (path == 4 && kind == 2 && y != 0) foreach (t.nm.rl.d[i]) y != t.nm.rl.d[i];
    if (path == 4 && kind == 3) y == t.nm.rl.k;
    if (path == 4 && kind == 4) a[t.nm.rl.k[1:0]] == 8'h5a;
    if (path == 4 && kind == 5) if (t.nm.rl != null) y == t.nm.rl.k;
    if (path == 4 && kind == 6) y == t.nm.rl.st[j];
    if (path == 5 && kind == 0 && randIndex) y == t.nm.nl.d[j];
    if (path == 5 && kind == 0 && !randIndex) y == t.nm.nl.d[s];
    if (path == 5 && kind == 1) foreach (t.nm.nl.d[i]) y != t.nm.nl.d[i];
    if (path == 5 && kind == 2 && y != 0) foreach (t.nm.nl.d[i]) y != t.nm.nl.d[i];
    if (path == 5 && kind == 3) y == t.nm.nl.k;
    if (path == 5 && kind == 4) a[t.nm.nl.k[1:0]] == 8'h5a;
    if (path == 5 && kind == 5) if (t.nm.nl != null) y == t.nm.nl.k;
    if (path == 5 && kind == 6) y == t.nm.nl.st[j];
  }
  function new(int path, int kind, bit randIndex);
    m = new;
    t = new;
    s = 1;
    this.path = path;
    this.kind = kind;
    this.randIndex = randIndex;
  endfunction
  // Make the handle at 'level' on the path null, from 1 nearest the variable
  function void nullAt(int level);
    case (path)
      0: begin if (level == 1) m = null; if (level == 2) m.rl = null; end
      1: begin if (level == 1) m = null; if (level == 2) m.nl = null; end
      2: begin if (level == 1) t = null; if (level == 2) t.rm = null; if (level == 3) t.rm.rl = null; end
      3: begin if (level == 1) t = null; if (level == 2) t.rm = null; if (level == 3) t.rm.nl = null; end
      4: begin if (level == 1) t = null; if (level == 2) t.nm = null; if (level == 3) t.nm.rl = null; end
      5: begin if (level == 1) t = null; if (level == 2) t.nm = null; if (level == 3) t.nm.nl = null; end
    endcase
  endfunction
  function Leaf leaf();
    case (path)
      0: return m.rl;
      1: return m.nl;
      2: return t.rm.rl;
      3: return t.rm.nl;
      4: return t.nm.rl;
      5: return t.nm.nl;
    endcase
  endfunction
endclass

module t;
  initial begin
    automatic int randomize_result;
    for (int path = 0; path < 6; ++path) begin
      for (int kind = 0; kind < 7; ++kind) begin
        for (int r = 0; r < 2; ++r) begin
          if (kind != 0 && r != 0) continue;
          for (int level = 0; level <= (path < 2 ? 2 : 3); ++level) begin
            automatic Paths p = new(path, kind, r[0]);
            automatic bit lastNull = level == (path < 2 ? 2 : 3);
            if (level != 0) p.nullAt(level);
            randomize_result = p.randomize();
            // A guard of the last handle being null keeps its read out
            `checkh(randomize_result, level == 0 || (kind == 5 && lastNull) ? 1 : 0);
            if (level == 0) begin
              automatic Leaf l = p.leaf();
              case (kind)
                0: `checkh(p.y, l.d[r[0] ? p.j : p.s])
                1: if (p.y == l.d[0] || p.y == l.d[1]) `stop;
                2: if (p.y != 0 && (p.y == l.d[0] || p.y == l.d[1])) `stop;
                4: `checkh(p.a[1], 8'h5a)
                6: `checkh(p.y, l.st[p.j])
                default: `checkh(p.y, l.k)
              endcase
            end
          end
        end
      end
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
