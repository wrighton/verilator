// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

typedef bit [64:0] wide_t;

// Element wider than 64 bits passed to a ref argument (IEEE 1800-2023 13.5.2)
function automatic wide_t add_ref(input wide_t v, ref wide_t data);
  add_ref = data;
  data = data + v;
endfunction

task automatic set_ref(input wide_t v, ref wide_t data);
  data = v;
endtask

typedef struct {
  int i;
  wide_t w;
} us_t;

class Cls;
  wide_t dyn[];
  wide_t w;
  function wide_t add(input wide_t v, ref wide_t data);
    add = data;
    data = data + v;
  endfunction
  // A const ref sees writes made to the actual during the call
  function void check_alias(input wide_t v, const ref wide_t cr);
    dyn[0] = v;
    `checkh(cr, v);
  endfunction
endclass

module t;
  wide_t dyn[];
  wide_t q[$];
  wide_t dyn2d[][];
  wide_t got;
  wide_t one;
  us_t us;
  us_t us_arr[2];
  Cls c;

  initial begin
    one = 65'(int'($c(1)));

    dyn = new[2];
    dyn[1] = {1'b1, 64'h10};
    got = add_ref(one, dyn[1]);
    `checkh(got, {1'b1, 64'h10});
    `checkh(dyn[1], {1'b1, 64'h11});
    set_ref({1'b1, 64'h1234}, dyn[1]);
    `checkh(dyn[1], {1'b1, 64'h1234});

    q = '{0, {1'b1, 64'h20}};
    got = add_ref(one, q[1]);
    `checkh(got, {1'b1, 64'h20});
    `checkh(q[1], {1'b1, 64'h21});

    dyn2d = new[2];
    dyn2d[1] = new[3];
    dyn2d[1][2] = {1'b1, 64'h30};
    got = add_ref(one, dyn2d[1][2]);
    `checkh(got, {1'b1, 64'h30});
    `checkh(dyn2d[1][2], {1'b1, 64'h31});

    c = new;
    c.dyn = new[1];
    c.dyn[0] = {1'b1, 64'h40};
    got = c.add(one, c.dyn[0]);
    `checkh(got, {1'b1, 64'h40});
    `checkh(c.dyn[0], {1'b1, 64'h41});

    c.check_alias(one << 64, c.dyn[0]);

    // Class and unpacked struct members
    c.w = {1'b1, 64'h50};
    got = add_ref(one, c.w);
    `checkh(got, {1'b1, 64'h50});
    `checkh(c.w, {1'b1, 64'h51});
    us.w = {1'b1, 64'h60};
    got = add_ref(one, us.w);
    `checkh(got, {1'b1, 64'h60});
    `checkh(us.w, {1'b1, 64'h61});
    us_arr[1].w = {1'b1, 64'h70};
    got = add_ref(one, us_arr[1].w);
    `checkh(got, {1'b1, 64'h70});
    `checkh(us_arr[1].w, {1'b1, 64'h71});

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
