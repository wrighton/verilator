// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0)
// verilog_format: on

// Functions with ref arguments that also access variables outside of themselves
// (so must be inlined), called with an element or member select as the argument

package pkg;
  bit cache[string];
  function bit check(string path);
    if (cache.exists(path)) return 1;
    cache[path] = 1;
    return 0;
  endfunction
  function automatic void rd(string path, ref int value);
    value = check(path) ? 2 : 1;
  endfunction
endpackage

class Mon;
  string paths[string];
  int seen;
  task run();
    foreach (paths[i]) begin
      automatic string key = i;
      automatic int v;
      fork
        forever begin
          #2;
          // 'v' is a member of the fork's dynamic scope
          pkg::rd(paths[key], v);
          seen += v;
        end
      join_none
    end
  endtask
endclass

class Obj;
  int x;
endclass

interface ifc;
  int sig;
endinterface

module t;
  // Automatic local by ref from a fork, function accesses a package variable
  initial begin
    automatic Mon m = new;
    m.paths["a"] = "x";
    m.paths["b"] = "y";
    m.run();
    #5;
    `checkd(m.seen, 6);
  end

  // The location is bound at the call, even if its index then changes
  int arr[4];
  int idx;
  function automatic void bumpIdx(ref int v);
    idx++;
    v = idx * 10;
  endfunction
  initial begin
    idx = 1;
    bumpIdx(arr[idx]);
    `checkd(arr[1], 20);
    `checkd(arr[2], 0);
  end

  // The location is bound at the call, even if its class handle then changes
  Obj obj;
  Obj objs[2];
  function automatic void swapObj(ref int v);
    obj = objs[1];
    v = 7;
  endfunction
  initial begin
    objs[0] = new;
    objs[1] = new;
    obj = objs[0];
    swapObj(obj.x);
    `checkd(objs[0].x, 7);
    `checkd(objs[1].x, 0);
  end

  // Nested selects, non-zero based range
  typedef struct {int f;} elem_t;
  typedef struct {elem_t e[3:1];} agg_t;
  agg_t agg[2];
  int count;
  function automatic void incr(ref int v, const ref int by);
    count++;
    v += by + count;
  endfunction
  int step[2];
  initial begin
    step[1] = 20;
    for (int i = 0; i < 2; ++i) begin
      for (int j = 1; j <= 3; ++j) begin
        incr(agg[i].e[j].f, step[1]);
      end
    end
    `checkd(agg[0].e[1].f, 21);
    `checkd(agg[0].e[3].f, 23);
    `checkd(agg[1].e[2].f, 25);
    `checkd(count, 6);
  end

  // Class handles that are queue and associative array elements
  Obj objq[$];
  Obj objm[string];
  initial begin
    automatic Obj o = new;
    #2;
    objq.push_back(o);
    o = new;
    objm["k"] = o;
    incr(objq[0].x, step[1]);
    incr(objm["k"].x, step[1]);
    `checkd(objq[0].x, 27);
    `checkd(objm["k"].x, 28);
  end

  // Virtual interface member
  ifc ifc0 ();
  initial begin
    automatic virtual ifc vif = ifc0;
    #1;
    pkg::rd("vif", vif.sig);
    pkg::rd("vif", vif.sig);
    `checkd(ifc0.sig, 2);
  end

  // Function with a return value
  int vals[3];
  int nCalls;
  function automatic int countSet(ref int v);
    nCalls++;
    v = nCalls * 3;
    return nCalls;
  endfunction
  initial begin
    for (int i = 0; i < 3; ++i) begin
      automatic int r = countSet(vals[i]);
      `checkd(r, i + 1);
    end
    `checkd(vals[0], 3);
    `checkd(vals[2], 9);
  end

  // Task (not inlined) waiting on a ref argument, from concurrent processes
  int chg[3];
  int hits[3];
  task automatic waitChg(ref int v, output int seen);
    @(v);
    seen = v;
  endtask
  initial begin
    for (int i = 0; i < 3; ++i) begin
      fork
        automatic int k = i;
        automatic int s;
        begin
          waitChg(chg[k], s);
          hits[k] = s;
        end
      join_none
    end
    #1;
    chg[0] = 5;
    chg[1] = 6;
    chg[2] = 7;
    #1;
    `checkd(hits[0], 5);
    `checkd(hits[1], 6);
    `checkd(hits[2], 7);
  end

  initial begin
    #30;
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
