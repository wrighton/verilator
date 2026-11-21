// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// A random index selects from the held elements of an array with rand_mode(0)
// (IEEE 1800-2023 18.8)

class Mem;
  rand int unsigned m[];
  constraint cm { m[0] < 100; }
endclass

class Arrays;
  rand int kd, kq, kf, ka, km;
  rand int unsigned d[];
  rand int unsigned q[$];
  rand bit [7:0] f[2:5];
  rand int unsigned aa[int];
  rand Mem o;
  constraint c {
    kd inside {[0:3]};
    d[kd] == 11;
    kq inside {[0:3]};
    q[kq] == 22;
    kf inside {[2:5]};
    f[kf] == 33;
    ka inside {1, 3, 7};
    aa[ka] == 44;
    km inside {[0:2]};
    o.m[km] == 55;
  }
  function new();
    d = new[4];
    q = '{0, 0, 0, 0};
    aa[1] = 0;
    aa[3] = 0;
    aa[7] = 0;
    o = new;
    o.m = new[3];
  endfunction
endclass

// Other uses of an array with rand_mode(0)
class Uses;
  rand int unsigned d[];
  rand int unsigned aa[string];
  rand int x, y;
  constraint c { d.sum() == x; y inside {d}; aa["k"] == 3; }
  function new();
    d = '{1, 7, 2};
    aa["k"] = 3;
  endfunction
endclass

module t;
  initial begin
    automatic Arrays a = new;
    automatic int ok;

    // Active: the solver picks the element
    ok = a.randomize();
    `checkd(ok, 1);
    `checkd(a.d[a.kd], 11);
    `checkd(a.f[a.kf], 33);
    `checkd(a.o.m[a.km], 55);

    a.d = '{0, 11, 0, 0};
    a.q = '{22, 0, 0, 0};
    a.f = '{0, 0, 33, 0};
    a.aa[1] = 0;
    a.aa[3] = 44;
    a.aa[7] = 0;
    a.o.m = '{0, 0, 55};
    a.d.rand_mode(0);
    a.q.rand_mode(0);
    a.f.rand_mode(0);
    a.aa.rand_mode(0);
    a.o.m.rand_mode(0);
    repeat (8) begin
      ok = a.randomize();
      `checkd(ok, 1);
      `checkd(a.kd, 1);
      `checkd(a.kq, 0);
      `checkd(a.kf, 4);
      `checkd(a.ka, 3);
      `checkd(a.km, 2);
      `checkd(a.d.size(), 4);
      `checkd(a.d[1], 11);
      `checkd(a.aa[3], 44);
    end

    begin
      automatic Uses u = new;
      u.d.rand_mode(0);
      u.aa.rand_mode(0);
      ok = u.randomize();
      `checkd(ok, 1);
      `checkd(u.x, 10);
      `checkd(u.y inside {1, 7, 2}, 1);
    end

    // No held element satisfies the constraint
    a.d = '{0, 0, 0, 0};
    ok = a.randomize();
    `checkd(ok, 0);

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
