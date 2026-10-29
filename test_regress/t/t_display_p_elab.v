// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2024 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checks(gotv,expv) do if ((gotv) != (expv)) begin $write("%%Error: %s:%0d:  got='%s' exp='%s'\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`ifdef verilator
 `define no_optimize(v) $c(v)
`else
 `define no_optimize(v) (v)
`endif
// verilog_format: on


module t;

  // $sformatf is not supported as parameter by some simulators

  parameter int I = 234;
  parameter string IS = $sformatf(">%p<", I);
  initial `checks(IS, ">234<");

  parameter real R = 1.234;
  parameter string RS = $sformatf(">%p<", R);
  initial `checks(RS, ">1.234<");

  int u[2];
  parameter int U[2] = '{5, 6};
  parameter string US = $sformatf(">%p<", U);
  initial `checks(US, ">'{'h5, 'h6}<");

`ifndef VERILATOR
  // Generally not supported by others
  parameter int Q[$] = '{1, 2};
  parameter string QS = $sformatf(">%p<", Q);
  initial `checks(QS, "x");

  // Generally not supported by others
  parameter int D[] = '{1, 2};
  parameter string DS = $sformatf(">%p<", D);
  initial `checks(DS, ">'{1, 2}<");

  parameter int A[int] = '{1: 10, 2: 20};
  parameter string AS = $sformatf(">%p<", A);
  initial `checks(AS, "x");

  typedef struct {int f, s;} s_t;
  parameter s_t S = '{f: 10, s: 20};
  parameter string SS = $sformatf(">%p<", S);
  initial `checks(SS, ">'{f:10, s:20}<");
`endif

  // Descending ranges print left to right, as an assignment pattern (IEEE 1800-2023 21.2.1.7)
  parameter int UD[1:0] = '{5, 6};
  parameter string UDS = $sformatf(">%p<", UD);
  initial `checks(UDS, ">'{'h5, 'h6}<");
  parameter int MD[1:0][0:1] = '{'{1, 2}, '{3, 4}};
  parameter string MDS = $sformatf(">%p<", MD);
  initial `checks(MDS, ">'{'{'h1, 'h2}, '{'h3, 'h4}}<");

  typedef struct {byte b[2:1];} sd_t;
  class Cd;
    int a[0:1][2:1];
  endclass
  typedef int ud_t[1:0];
  ud_t ud;
  int md[2:1][1:0];
  int sl[7:0];
  sd_t sd;
  Cd cd;
  initial begin
    string ds;
    #1;
    ud[1] = `no_optimize(5);
    ud[0] = `no_optimize(6);
    ds = $sformatf(">%p<", ud);
    `checks(ds, ">'{'h5, 'h6}<");
    md[2][1] = `no_optimize(1);
    md[2][0] = `no_optimize(2);
    md[1][1] = `no_optimize(3);
    md[1][0] = `no_optimize(4);
    ds = $sformatf(">%p<", md);
    `checks(ds, ">'{'{'h1, 'h2}, '{'h3, 'h4}}<");
    for (int i = 0; i < 8; ++i) sl[i] = `no_optimize(i);
    ds = $sformatf(">%p<", sl[6:4]);
    `checks(ds, ">'{'h6, 'h5, 'h4}<");
    sd.b[2] = `no_optimize(1);
    sd.b[1] = `no_optimize(2);
    ds = $sformatf(">%p<", sd);
    `checks(ds, ">'{b:'{'h1, 'h2}}<");
    cd = new;
    cd.a[0][2] = `no_optimize(1);
    cd.a[0][1] = `no_optimize(2);
    cd.a[1][2] = `no_optimize(3);
    cd.a[1][1] = `no_optimize(4);
    ds = $sformatf(">%p<", cd);
    `checks(ds, ">'{a:'{'{'h1, 'h2}, '{'h3, 'h4}}}<");
  end

  // Original issue
  function integer infofunc();
    $info("%p", U);
    return 0;
  endfunction
  localparam integer return_val = infofunc();

  string s;

  initial begin
    #1;
    u[0] = `no_optimize(5);
    u[1] = `no_optimize(6);
    s = $sformatf(">%p<", u);
    `checks(s, ">'{'h5, 'h6}<");

    `checks(US, ">'{'h5, 'h6}<");
    $write("*-* All Finished *-*\n");
    $finish;
  end

endmodule
