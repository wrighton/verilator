// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2024 Antmicro Ltd
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define check_rand(cl, field, cond) \
begin \
  automatic longint prev_result; \
  automatic int ok; \
  if (!bit'(cl.randomize())) $stop; \
  prev_result = longint'(field); \
  if (!(cond)) $stop; \
  repeat(9) begin \
    longint result; \
    if (!bit'(cl.randomize())) $stop; \
    result = longint'(field); \
    if (!(cond)) $stop; \
    if (result != prev_result) ok = 1; \
    prev_result = result; \
  end \
  if (ok != 1) $stop; \
end
`define check_rand_min_count(cl, field, exp_val, min_count) \
begin \
  automatic longint prev_result; \
  automatic int ok, count = 0; \
  if (!bit'(cl.randomize())) $stop; \
  prev_result = longint'(field); \
  if (field == exp_val) count++; \
  repeat(99) begin \
    longint result; \
    if (!bit'(cl.randomize())) $stop; \
    result = longint'(field); \
    if (field == exp_val) count++; \
    if (result != prev_result) ok = 1; \
    prev_result = result; \
  end \
  if (count < min_count) $stop; \
end
// verilog_format: on

class C;
  rand int x;
  int q[$] = {0, 0, 0, 0, 0};
  constraint fore {
    x < 7;
    foreach(q[i])
      x > i;
    foreach(q[i])  // loop again with the same index name
      x > i;
  };
endclass

class D;
  rand bit posit;
  rand int x;
  int o[$];  // empty
  int p[$] = {1};
  int q[$] = {0, 0, 0, 0, 0};
  constraint fore {
    if (posit == 1) {
      foreach(o[i]) o[i] > 0;
    }
    if (posit == 1) {
      foreach(p[i]) p[i] > 0;
    }
    if (posit == 1) {
      x < 7;
      foreach(q[i])
        x > i;
    } else {
      x > -3;
      foreach(q[i])
        x < i;
    }
  };
endclass

class E;
  typedef struct { rand bit [31:0]a; } cfg_t;
  rand cfg_t cfg[];

  function new();
    cfg = new [10];
  endfunction

  constraint e {
    foreach (cfg[i]) {
      // (i/2)*2 math is used to make sure we use i in array index and
      // not exceed table size
      solve cfg[(i/2)*2].a before cfg[(i/2)*2 + 1].a ;
      cfg[(i/2)*2 + 1].a != cfg[(i/2)*2].a;
    }
  }
endclass

class F;
  typedef struct { rand bit c; rand bit [7:0]d; }subcfg_t;
  typedef struct { subcfg_t subcfg[]; } cfg_t;
  rand cfg_t cfg[];
  rand bit b;

  function new();
    cfg = new [10];
    foreach (cfg[i]) begin
      cfg[i].subcfg = new [10];
    end
  endfunction

  constraint f {
    foreach (cfg[i]) {
      solve b before cfg[i].subcfg[0].d;
      cfg[i].subcfg[0].d[0] != b;
    }
  }
endclass

class G;
  typedef struct { rand bit [31:0]a; rand bit c; } cfg_t;
  rand cfg_t cfg[];
  rand bit b;

  function new();
    cfg = new [6];
  endfunction

  constraint g {
    foreach (cfg[i]) {
      solve b before cfg[i].a, cfg[i].c;

      b -> cfg[i].c == 1;
      b -> cfg[i].a == 0;
    }
  }
endclass

class ImplyItem;
  rand bit flag;
endclass

class ImplyHandleArray;
  rand ImplyItem items[];
  rand bit all_flags;

  function new();
    items = new [3];
    foreach (items[i]) items[i] = new;
  endfunction

  constraint c_imply {
    foreach (items[i]) {
      if (i < 5) {
        all_flags -> items[i].flag;
        !items[i].flag -> !all_flags;
      }
    }
  }
  constraint c_select {
    foreach (items[i]) {
      if (all_flags) items[i].flag;
      else !items[i].flag;
    }
  }
endclass

class H;
  rand integer a[];
  rand integer b;

  function new();
    a = new [6];
  endfunction

  constraint h {
    foreach (a[i]) {
      solve b before a[i];

      a[i] != b;
    }
  }
endclass

class I;
  rand int a;
  rand int arr[];
  constraint c1 {
    arr.size() == 5;
    foreach(arr[i]) {
      arr[i] inside {[10 : 200]};
    }
  }
  constraint c2 {
     a + arr.sum() == 200;
  }
endclass

class J;
  rand int a;
  rand int arr[];

  function new();
    arr = new [5];
  endfunction

  constraint c1 {
    foreach(arr[i]) {
      arr[i] inside {[10 : 200]};
    }
  }
  constraint c2 {
     a + arr.sum() == 200;
  }
endclass

class CaptureMatrix;
  rand int matrix[2][3];
  rand int cube[2][2][2];
endclass

module t;
  initial begin
    automatic C c = new;
    automatic D d = new;
    automatic E e = new;
    automatic F f = new;
    automatic G g = new;
    automatic H h = new;
    automatic I i = new;
    automatic J j = new;

    `check_rand(c, c.x, 4 < c.x && c.x < 7);
    `check_rand(d, d.posit, (d.posit ? 4 : -3) < d.x && d.x < (d.posit ? 7 : 0));
    foreach (e.cfg[i]) begin
      `check_rand(e, e.cfg[i].a, (e.cfg[(i/2)*2].a != e.cfg[(i/2)*2 + 1].a));
    end
    foreach (f.cfg[i]) begin
      `check_rand(f, f.cfg[i].subcfg[0].d, (f.cfg[i].subcfg[0].d[0] != f.b));
    end
    foreach (g.cfg[i]) begin
      `check_rand_min_count(g, g.cfg[i].a, 0, 14);
    end
    // A bare one-bit member of an array element as an implication or if/else arm stays a
    // solver variable.
    begin
      automatic ImplyHandleArray imply = new;
      automatic int randomize_result;
      repeat (20) begin
        randomize_result = imply.randomize();
        `checkd(randomize_result, 1)
        foreach (imply.items[k]) `checkd(imply.items[k].flag, imply.all_flags)
      end
      imply.c_select.constraint_mode(0);
      repeat (20) begin
        randomize_result = imply.randomize() with {all_flags == 1;};
        `checkd(randomize_result, 1)
        foreach (imply.items[k]) `checkd(imply.items[k].flag, 1'b1)
      end
    end
    foreach (h.a[i]) begin
      `check_rand(h, h.a[i], (h.a[i] != h.b));
    end
    `check_rand(i, i.a, (i.arr.sum() + i.a == 200));
    foreach (i.arr[it]) begin
      `check_rand(i, i.arr[it], (i.arr[it] inside {[10 : 200]}));
    end
    `check_rand(j, j.a, (j.arr.sum() + j.a == 200));
    foreach (j.arr[i]) begin
      `check_rand(j, j.arr[i], (j.arr[i] inside {[10 : 200]}));
    end
    begin
      automatic CaptureMatrix c = new;
      automatic int offset;
      automatic int randomize_result;
      // Later indices are local to their header, while a caller loop index is captured.
      for (int j = 0; j < 4; j++) begin
        offset = j + 7;
        randomize_result = c.randomize() with {
          foreach (matrix[i, k]) matrix[i][k] == 100 * j + 10 * i + k;
          foreach (cube[i, k, l]) cube[i][k][l] == 100 * i + 10 * k + l + offset;
        };
        `checkd(randomize_result, 1);
        foreach (c.matrix[i, k]) `checkd(c.matrix[i][k], 100 * j + 10 * i + k);
        foreach (c.cube[i, k, l]) `checkd(c.cube[i][k][l], 100 * i + 10 * k + l + offset);
      end
      // A nested header with an omitted first dimension still owns its j index.
      randomize_result = c.randomize() with {
        foreach (matrix[i]) {
          foreach (matrix[, j]) matrix[i][j] == 16 * i + j + offset;
        }
      };
      `checkd(randomize_result, 1);
      foreach (c.matrix[i, j]) `checkd(c.matrix[i][j], 16 * i + j + offset);
    end
    begin
      automatic int matrix[2][3];
      automatic int offset = 19;
      automatic int randomize_result;
      randomize_result = std::randomize(matrix) with {
        foreach (matrix[i, j]) matrix[i][j] == 16 * i + j + offset;
      };
      `checkd(randomize_result, 1);
      foreach (matrix[i, j]) `checkd(matrix[i][j], 16 * i + j + offset);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
