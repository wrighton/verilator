// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2023 Antmicro Ltd
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

class Foo;
  task do_something(int arg_v, int arg_aa[int]);
    int dynscope_var;
    int x;
    int aa[int];
    int da[] = new[2];
    int q[$] = {0, 0};
    int fa[2];
    if (dynscope_var != 0) $stop;
    dynscope_var = 10;
    if (dynscope_var != 10) $stop;

    fork
      #10 begin
        x = 0;
        // Test writing elements of containers moved to the dynamic scope
        aa[1] = 10;
        da[1] = 11;
        q[1] = 12;
        fa[1] = 13;
        arg_aa[1] = 14;
        `checkd(aa[1], 10);
        `checkd(da[1], 11);
        `checkd(q[1], 12);
        `checkd(fa[1], 13);
        `checkd(arg_aa[1], 14);
        aa[1] += 1;
        ++arg_aa[1];
        `checkd(aa[1], 11);
        `checkd(arg_aa[1], 15);
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

  // Test writing elements of inout and output container arguments in a fork
  task write_arg_elems(inout int io_aa[int], output int o_aa[int]);
    fork
      begin
        io_aa[1] = 16;
        o_aa[1] = 17;
      end
      #1;
    join_any
  endtask
endclass

module t;
  initial begin
    Foo foo;
    foo = new;
    foo.do_something(0, '{default: 0});
    begin
      int io_aa[int];
      int o_aa[int];
      foo.write_arg_elems(io_aa, o_aa);
      `checkd(io_aa[1], 16);
      `checkd(o_aa[1], 17);
    end

    #99 begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
