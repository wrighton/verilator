// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2023 Antmicro Ltd
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Writes to elements of containers moved into a dynamic scope

class item_c;
  int v;
  function new(int v);
    this.v = v;
  endfunction
endclass

class seq_c;
  int done;

  // Mutating methods on elements of an associative array of queues
  task body();
    item_c pool[$];
    item_c parts[int][$];
    for (int k = 0; k < 4; k++) begin
      item_c it = new(k);
      pool.push_back(it);
    end
    for (int i = 0; i < 2; i++) begin
      parts[i] = {};
      for (int j = 0; j < 2; j++) parts[i].push_back(pool[2 * i + j]);
    end
    fork
      begin
        foreach (parts[i]) begin
          automatic int ii = i;
          fork
            begin
              #1;
              done += parts[ii].size();
              parts[ii].push_front(pool[ii]);
            end
          join_none
        end
        wait fork;
      end
    join
    `checkd(parts[0].size(), 3);
    `checkd(parts[1][0].v, 1);
    `checkd(parts[1][2].v, 3);
  endtask

  // Element writes and nested containers, inside and outside the forks
  task elems();
    int aa[int];
    int wc[*];
    int nested[string][int][$];
    item_c handles[string];
    aa[3] = 30;
    wc[4'd5] = 50;
    nested["a"][1].push_back(10);
    handles["x"] = new(7);
    fork
      begin
        #1;
        aa[3] += 1;
        aa[4] = 40;
        wc[4'd5]++;
        nested["a"][1].push_back(11);
        nested["b"][2] = {12};
        handles["y"] = new(9);
      end
    join_none
    wait fork;
    `checkd(aa.size(), 2);
    `checkd(aa[3], 31);
    `checkd(aa[4], 40);
    `checkd(wc[4'd5], 51);
    `checkd(nested["a"][1].size(), 2);
    `checkd(nested["a"][1][1], 11);
    `checkd(nested["b"][2][0], 12);
    `checkd(handles.size(), 2);
    `checkd(handles["y"].v, 9);
    nested["a"][1] = {};
    `checkd(nested["a"][1].size(), 0);
  endtask

  // Element writes to an inout argument, which is copied into the dynamic scope
  task args(inout int a[int]);
    fork
      begin
        a[1] = 100;
        a.delete(2);
      end
    join_none
    #0;
  endtask
endclass

class Foo;
  task do_something(int arg_v);
    int dynscope_var;
    int x;
    if (dynscope_var != 0) $stop;
    dynscope_var = 10;
    if (dynscope_var != 10) $stop;

    fork
      #10 begin
        x = 0;
        // Test capturing a variable that needs to be modified
        if (dynscope_var != 10) $stop;
        $display("Incremented dynscope_var: %0d", ++dynscope_var);
        if (dynscope_var != 11) $stop;

        // Check nested access
        fork
          #10 begin
            $display("Incremented x: %0d", ++x);
            $display("Incremented dynscope_var: %0d", ++dynscope_var);
            if (dynscope_var != 12) $stop;
          end
        join_none
      end
      #10 begin
        // Same as the first check, but with an argument
        // (so it needs to be copied to the dynamic scope instead of being moved there)
        if (arg_v != 1) $stop;
        $display("Incremented arg_v: %0d", ++arg_v);
        if (arg_v != 2) $stop;
      end
    join_none

    // Check if regular access to arg_v has been substituted with access to its copy from
    // a dynamic scope
    $display("Incremented arg_v: %0d", ++arg_v);
    if (arg_v != 1) $stop;
  endtask
endclass

module t;
  initial begin
    Foo foo;
    foo = new;
    foo.do_something(0);
    begin
      seq_c s;
      int a[int];
      s = new;
      s.body();
      `checkd(s.done, 4);
      s.elems();
      a[2] = 2;
      s.args(a);
      `checkd(a.size(), 1);
      `checkd(a[1], 100);
    end

    #99 begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
