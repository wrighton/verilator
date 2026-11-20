// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checks(gotv,expv) do if ((gotv) != (expv)) begin $write("%%Error: %s:%0d:  got='%s' exp='%s'\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Structures, unions and enumerations of the same name in different scopes, as type parameter
// values, make different specializations

class CA;
  typedef struct {int v;} s_t;
  typedef enum {
    E0,
    E1
  } e_t;
endclass

class CB;
  typedef struct {int v;} s_t;
  typedef enum {
    E0,
    E1
  } e_t;
endclass

interface Sink #(
    type T = int
);
  T v;
endinterface

module sub;
  typedef union packed {logic [7:0] v;} u_t;
  Sink #(.T(u_t)) su ();
  function automatic string tname();
    return $typename(su.v);
  endfunction
  function automatic string uname();
    return $typename(u_t);
  endfunction
endmodule

module t;
  Sink #(.T(CA::s_t)) sa ();
  Sink #(.T(CB::s_t)) sb ();
  Sink #(.T(CA::e_t)) ea ();
  Sink #(.T(CB::e_t)) eb ();
  sub u1 ();
  for (genvar i = 0; i < 2; i++) begin : g
    typedef struct {int v;} s_t;
    Sink #(.T(s_t)) sg ();
    sub u ();
    function automatic string tname();
      return $typename(sg.v);
    endfunction
    function automatic string sname();
      return $typename(s_t);
    endfunction
  end

  initial begin
    `checks($typename(sa.v), $typename(CA::s_t));
    `checks($typename(sb.v), $typename(CB::s_t));
    `checks($typename(ea.v), $typename(CA::e_t));
    `checks($typename(eb.v), $typename(CB::e_t));
    `checks(g[0].tname(), g[0].sname());
    `checks(g[1].tname(), g[1].sname());
    `checks(g[1].u.tname(), g[1].u.uname());
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
