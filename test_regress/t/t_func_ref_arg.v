// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2023 Antmicro Ltd
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define checks(gotv,expv) do if ((gotv) != (expv)) begin $write("%%Error: %s:%0d:  got='%s' exp='%s'\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define checkr(gotv,expv) do if ((gotv) != (expv)) begin $write("%%Error: %s:%0d:  got=%f exp=%f\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

class MyInt;
  int x;
  function new(int a);
    x = a;
  endfunction
endclass

function int get_val_set_5(ref int x);
  automatic int y = x;
  x = 5;
  return y;
endfunction

function int get_val(const ref int x);
  return x;
endfunction

function automatic int set_get(ref int aa[int], input int k, const ref int x);
  aa[k] = 7;
  return x;
endfunction

class Cls;
  function int get_val_set_2(ref int x);
    automatic int y = x;
    x = 2;
    return y;
  endfunction
endclass

typedef struct {MyInt arr[2][][$];} struct_t;

class Opaque;
  string s;
  real r;
endclass

task automatic append_x(ref string s);
  s = {s, "x"};
endtask

function automatic string get_str(const ref string s);
  return s;
endfunction

task automatic add_half(ref real r);
  r = r + 0.5;
endtask

function automatic real get_real(const ref real r);
  return r;
endfunction

module t;
  int a, b;
  int arr[1];
  int dyn_arr[];
  int dyn_arr_2d[][];
  struct_t st;
  Cls cls;
  MyInt mi;
  initial begin
    a = 10;
    b = get_val_set_5(a);
    `checkh(a, 5);
    `checkh(b, 10);

    cls = new;
    b = cls.get_val_set_2(a);
    `checkh(a, 2);
    `checkh(b, 5);

    mi = new(1);
    b = cls.get_val_set_2(mi.x);
    `checkh(mi.x, 2);
    `checkh(b, 1);

    arr[0] = 10;
    b = cls.get_val_set_2(arr[0]);
    `checkh(arr[0], 2);
    `checkh(b, 10);

    dyn_arr = new[3];
    dyn_arr[1] = 10;
    b = get_val_set_5(dyn_arr[1]);
    `checkh(dyn_arr[1], 5);
    `checkh(b, 10);
    b = cls.get_val_set_2(dyn_arr[1]);
    `checkh(dyn_arr[1], 2);
    `checkh(b, 5);

    dyn_arr_2d = new[2];
    dyn_arr_2d[0] = new[4];
    dyn_arr_2d[0][1] = 10;
    b = get_val_set_5(dyn_arr_2d[0][1]);
    `checkh(dyn_arr_2d[0][1], 5);
    `checkh(b, 10);
    b = cls.get_val_set_2(dyn_arr_2d[0][1]);
    `checkh(dyn_arr_2d[0][1], 2);
    `checkh(b, 5);

    st.arr[1] = new[3];
    st.arr[1][2][0] = new(10);
    b = get_val_set_5(st.arr[1][2][0].x);
    `checkh(st.arr[1][2][0].x, 5);
    `checkh(b, 10);
    b = cls.get_val_set_2(st.arr[1][2][0].x);
    `checkh(st.arr[1][2][0].x, 2);
    `checkh(b, 5);

    // Elements by a variable index, which may exceed the array
    for (int i = 0; i < 1; ++i) `checkh(get_val(arr[i]), 2);
    begin
      int arr3[3];
      int idx;
      for (int i = 0; i < 3; ++i) begin
        arr3[i] = i + 10;
        `checkh(get_val(arr3[i]), i + 10);
      end
      // Out of bounds, reads the default value (IEEE 1800-2023 7.4.6)
      idx = $c(3);
      b = 5;
      b = get_val(arr3[idx]);
      `checkh(b, 0);
    end

    begin
      int assoc[int];
      int wild[*];
      int assoc_2d[string][int];
      assoc[-3] = 10;
      b = get_val_set_5(assoc[-3]);
      `checkh(assoc[-3], 5);
      `checkh(b, 10);
      b = cls.get_val_set_2(assoc[-3]);
      `checkh(assoc[-3], 2);
      `checkh(b, 5);
      // Missing element is created
      b = get_val_set_5(assoc[a]);
      `checkh(assoc[2], 5);
      `checkh(b, 0);
      `checkh(assoc.size(), 2);
      // A const ref sees a write made to the element during the call
      b = set_get(assoc, -3, assoc[-3]);
      `checkh(b, 7);

      wild[8'h7] = 10;
      b = get_val_set_5(wild[8'h7]);
      `checkh(wild[8'h7], 5);
      `checkh(b, 10);

      assoc_2d["k"][1] = 10;
      b = cls.get_val_set_2(assoc_2d["k"][1]);
      `checkh(assoc_2d["k"][1], 2);
      `checkh(b, 10);
    end

    // Opaque types, elements of arrays and class members
    begin
      automatic Opaque op = new;
      automatic string sa[2] = '{"a", "b"};
      automatic real ra[2] = '{1.0, 2.0};
      append_x(sa[1]);
      `checks(sa[1], "bx");
      `checks(get_str(sa[1]), "bx");
      op.s = "c";
      append_x(op.s);
      `checks(op.s, "cx");
      add_half(ra[0]);
      `checkr(ra[0], 1.5);
      op.r = 3.0;
      add_half(op.r);
      `checkr(op.r, 3.5);
      `checkr(get_real(ra[0]), 1.5);
      `checkr(get_real(op.r), 3.5);
    end

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
