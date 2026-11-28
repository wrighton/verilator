// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Reading past the end of a queue or dynamic array of structs gives the members' initial
// assignments (IEEE 1800-2023 7.4.6), also after a literal is assigned to it

module t;
  typedef struct {
    bit [7:0] v = 8'h5a;
    bit [7:0] w;
  } elem_t;
  typedef elem_t elem_q_t[$];

  elem_t q[$];
  elem_t d[];
  elem_q_t qq[$];

  function automatic elem_q_t make_q();
    elem_q_t r;
    r.push_back('{v: 8'h22, w: 8'h23});
    return r;
  endfunction

  initial begin
    q = '{'{v: 8'h11, w: 8'h12}};
    d = '{'{v: 8'h11, w: 8'h12}, '{v: 8'h13, w: 8'h14}};
    `checkh(q[0].v, 8'h11);
    `checkh(q[1].v, 8'h5a);
    `checkh(q[1].w, 8'h00);
    `checkh(d[2].v, 8'h5a);
    `checkh(make_q()[3].v, 8'h5a);
    q = make_q();
    `checkh(q[1].v, 8'h5a);
    qq.push_back(q);
    qq[0] = '{'{v: 8'h66, w: 8'h67}};
    `checkh(qq[0][1].v, 8'h5a);
    `checkh(qq[3][0].v, 8'h5a);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
