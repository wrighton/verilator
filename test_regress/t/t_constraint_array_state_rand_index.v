// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// An element of an array that is not random, selected by a random index, reads the elements as
// they are when randomize() is called, and zero out of range (IEEE 1800-2023 7.4.6)

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// verilator lint_off WIDTH

class Lut;
  bit [1:0] lut[4];
  rand bit [1:0] lj;
  rand bit [6:0] arr[4];
  constraint c {
    lut[lj] == 2'd0;
    arr[lut[lj + 2'd1]] == 7'd40;
  }
  function new();
    lut = '{2'd1, 2'd2, 2'd0, 2'd3};
  endfunction
endclass

// As the index of a member of an object of a rand class handle array
class Item;
  rand bit [6:0] v;
endclass

class Holder;
  rand Item items[4];
  bit [1:0] lut[4];
  rand bit [1:0] lj;
  constraint c {items[lut[lj]].v == 7'd40;}
  function new();
    foreach (items[i]) items[i] = new;
    lut = '{2'd1, 2'd2, 2'd0, 2'd2};
  endfunction
endclass

// A queue, a dynamic array, and an array of queues
class Queues;
  int q[$];
  int d[];
  bit [7:0] qa[3][$];
  rand bit [2:0] k;
  rand bit [2:0] m;
  rand int i;
  constraint c {
    q[k] == 7;
    d[m] == 30;
    i inside {[0 : 2]};
    qa[i][2] == 8'd7;
  }
  function new();
    q = '{1, 7, 3, 4};
    d = '{10, 20, 30};
    qa[0] = '{1, 2, 3};
    qa[1] = '{4, 5, 7};
    qa[2] = '{8, 9};
  endfunction
endclass

// Through random indices into two dimensions
class TwoKeys;
  bit [6:0] lut[4][4];
  bit [7:0] qa[3][$];
  int wanted;
  rand bit [1:0] row, col;
  rand bit [1:0] i, k;
  constraint c {
    lut[row][col] == 7'(wanted);
    i < 3;
    qa[i][k] == 8'd9;
  }
  function new();
    foreach (lut[a, b]) lut[a][b] = 7'(a * 4 + b + 1);
    qa[0] = '{1, 2, 3};
    qa[1] = '{4, 5};
    qa[2] = '{6, 7, 8, 9};
  endfunction
endclass

// Declared from a low bound, descending, of two dimensions, and with more elements than an
// index reaches
class Ranges;
  bit [3:0] down[7:4];
  bit [3:0] grid[2][3];
  bit [7:0] five[5];
  rand bit [2:0] k;
  rand bit [1:0] r;
  rand bit [1:0] n;
  constraint c {
    k inside {[4 : 7]};
    down[k] == 4'd9;
    r < 3;
    grid[1][r] == 4'd5;
    five[n] == 8'h87;
  }
  function new();
    down = '{4'd1, 4'd9, 4'd3, 4'd4};
    grid = '{'{4'd1, 4'd2, 4'd3}, '{4'd4, 4'd6, 4'd5}};
    five = '{8'h81, 8'h83, 8'h85, 8'h87, 8'h89};
  endfunction
endclass

// Through another index, not solved, of a subarray, which reads the default out of range
class SubRange;
  bit [7:0] lut2[3][4];
  int s;
  rand bit [1:0] j;
  rand bit [1:0] i;
  rand bit [7:0] y;
  rand bit [7:0] z;
  constraint c {
    y == lut2[s][j];
    i < 3;
    z == lut2[i][s];
  }
  function new();
    foreach (lut2[a, b]) lut2[a][b] = 8'(a * 16 + b + 1);
  endfunction
endclass

// Below a negative low bound: a signed index, an index that is an int, and a 65-bit index
// that is not random
class Signed;
  bit [6:0] lut[-2:3][8:5];
  int s;
  bit [31:0] u;
  bit [64:0] w;
  bit signed [4:0] s5;
  bit [4:0] u5;
  bit [6:0] grid[4][4];
  int want;
  rand bit signed [5:0] key;
  rand bit signed [39:0] wkey;
  rand bit [3:0] jj;
  rand bit [6:0] y;
  rand bit [6:0] z;
  rand bit [6:0] v;
  rand bit [6:0] y5;
  rand bit [6:0] z5;
  rand bit [1:0] gj;
  rand bit [6:0] gv;
  constraint c {
    lut[key][5] == 7'(want);
    lut[wkey][6] == 7'(want + 1);
    jj inside {[5 : 8]};
    y == lut[s][jj];
    z == lut[u][jj];
    v == lut[w][jj];
    y5 == lut[s5][jj];
    z5 == lut[u5][jj];
    gv == grid[w][gj];
  }
  function new();
    foreach (lut[a, b]) lut[a][b] = 7'((a + 2) * 4 + (b - 5) + 1);
    foreach (grid[a, b]) grid[a][b] = 7'(a * 4 + b + 1);
  endfunction
endclass

// Out of range, which reads the default (IEEE 1800-2023 7.4.6, 7.10.1)
class Outside;
  bit [1:0] lut[4];
  int q[$];
  int e[$];
  rand bit [2:0] j;
  rand bit [2:0] k;
  rand bit [1:0] h;
  constraint c {
    lut[j] == 2'd0;
    q[k] == 0;
    e[h] == 0;
  }
  function new();
    lut = '{2'd1, 2'd2, 2'd3, 2'd1};
    q = '{1, 2, 3};
  endfunction
endclass

// A large array, read four times
class Large;
  int big[4096];
  rand bit [15:0] i0, i1, i2, i3;
  constraint c {
    i0 < 4096;
    i1 < 4096;
    i2 < 4096;
    i3 < 4096;
    big[i0] == -1;
    big[i1] == -2;
    big[i2] == -3;
    big[i3] == -4;
  }
  function new();
    foreach (big[n]) big[n] = n;
    big[4091] = -1;
    big[7] = -2;
    big[2048] = -3;
    big[4095] = -4;
  endfunction
endclass

module t;
  initial begin
    automatic Lut lt = new;
    automatic Ranges rg = new;
    automatic Outside os = new;
    automatic Large lg = new;
    automatic Holder ho = new;
    automatic Queues qs = new;
    automatic SubRange sr = new;
    automatic TwoKeys tk = new;
    automatic Signed sg = new;
    automatic int ok;
    // 32'hffff_fffe is the int -2
    sg.u = 32'hffff_fffe;
    for (int row = -3; row <= 4; ++row) begin
      sg.want = 4 * (row + 2) + 1;
      sg.s = row;
      sg.s5 = 5'(row);
      sg.u5 = 5'(row);
      // The largest value is out of range, though its position wraps to 1
      sg.w = row[0] ? '1 : 65'(row + 2);
      ok = sg.randomize();
      if (row < -2 || row > 3) begin
        `checkd(ok, 0);
      end
      else begin
        `checkd(ok, 1);
        `checkd(sg.key, row);
        `checkd(sg.wkey, row);
        `checkd(sg.y, sg.lut[row][sg.jj]);
        `checkd(sg.y5, sg.lut[row][sg.jj]);
        if (row < 0) begin
          `checkd(sg.z5, 0);
        end
        else begin
          `checkd(sg.z5, sg.lut[row][sg.jj]);
        end
        `checkd(sg.z, sg.lut[-2][sg.jj]);
        if (row[0] || row > 1) begin
          `checkd(sg.v, 0);
          `checkd(sg.gv, 0);
        end
        else begin
          `checkd(sg.v, sg.lut[row+2][sg.jj]);
          `checkd(sg.gv, sg.grid[row+2][sg.gj]);
        end
      end
    end
    for (int w = 1; w <= 16; ++w) begin
      tk.wanted = w;
      ok = tk.randomize();
      `checkd(ok, 1);
      `checkd(tk.lut[tk.row][tk.col], w);
      `checkd(tk.i, 2);
      `checkd(tk.k, 3);
    end
    repeat (8) begin
      sr.s = 5;
      ok = sr.randomize();
      `checkd(ok, 1);
      `checkd(sr.y, 0);
      `checkd(sr.z, 0);
      sr.s = 2;
      ok = sr.randomize();
      `checkd(ok, 1);
      `checkd(sr.y, sr.lut2[2][sr.j]);
      `checkd(sr.z, sr.lut2[sr.i][2]);
      ok = qs.randomize();
      `checkd(ok, 1);
      `checkd(qs.k, 1);
      `checkd(qs.m, 2);
      `checkd(qs.i, 1);
      ok = ho.randomize();
      `checkd(ok, 1);
      `checkd(ho.items[ho.lut[ho.lj]].v, 40);
      ok = lt.randomize();
      `checkd(ok, 1);
      `checkd(lt.lj, 2);
      `checkd(lt.arr[lt.lut[lt.lj+2'd1]], 40);
      ok = rg.randomize();
      `checkd(ok, 1);
      `checkd(rg.k, 6);
      `checkd(rg.r, 2);
      `checkd(rg.n, 3);
      ok = os.randomize();
      `checkd(ok, 1);
      `checkd(os.j >= 4, 1'b1);
      `checkd(os.k >= 3, 1'b1);
    end
    repeat (2) begin
      ok = lg.randomize();
      `checkd(ok, 1);
      `checkd(lg.i0, 4091);
      `checkd(lg.i1, 7);
      `checkd(lg.i2, 2048);
      `checkd(lg.i3, 4095);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
