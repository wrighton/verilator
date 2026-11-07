// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2023 Antmicro Ltd
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
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

function automatic int get_val(const ref int x);
  return x;
endfunction

function automatic int get_val_input(input int x);
  return x;
endfunction

// Return the reference after writing the array element it refers to
function automatic int set_get(ref int aa[int], input int k, const ref int x);
  aa[k] = 7;
  return x;
endfunction

int key_calls = 0;
function automatic int next_key();
  ++key_calls;
  return key_calls + 100;
endfunction

// Element of a const ref array
function automatic int get_elem(const ref int aa[int], input int k);
  return get_val(aa[k]);
endfunction

// Element of an input array, which is a local copy
function automatic int get_elem_input(input int aa[int], input int k);
  void'(get_val(aa[k]));
  return aa.num();
endfunction

typedef struct {
  int x;
  int y;
} xy_t;

typedef struct {int m[int];} has_assoc_t;

class Cls;
  int m[int];
  const int cm[int] = '{1: 2};
  function int get_m(int k);
    return get_val(m[k]);
  endfunction
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

module sub (
    input int in_aa[int]
);
  // Element of an input port array
  function automatic int get_in_elem(input int k);
    return get_val(in_aa[k]);
  endfunction
endmodule

module t (
    input clk
);
  int a, b;
  int arr[1];
  int dyn_arr[];
  int dyn_arr_2d[][];
  struct_t st;
  Cls cls;
  MyInt mi;
  int in_aa[int];
  sub sub_i (.in_aa(in_aa));
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
    `checkd(get_val(arr[0]), 2);

    dyn_arr = new[3];
    dyn_arr[1] = 10;
    b = get_val_set_5(dyn_arr[1]);
    `checkh(dyn_arr[1], 5);
    `checkh(b, 10);
    b = cls.get_val_set_2(dyn_arr[1]);
    `checkh(dyn_arr[1], 2);
    `checkh(b, 5);
    `checkd(get_val(dyn_arr[1]), 2);

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
      `checkd(assoc[-3], 5);
      `checkd(b, 10);
      b = cls.get_val_set_2(assoc[-3]);
      `checkd(assoc[-3], 2);
      `checkd(b, 5);
      // Missing element is created
      b = get_val_set_5(assoc[a]);
      `checkd(assoc[2], 5);
      `checkd(b, 0);
      `checkd(assoc.size(), 2);
      // Reference follows a write to the element during the call
      b = set_get(assoc, -3, assoc[-3]);
      `checkd(b, 7);
      `checkd(get_val(assoc[-3]), 7);

      wild[8'h7] = 10;
      b = get_val_set_5(wild[8'h7]);
      `checkd(wild[8'h7], 5);
      `checkd(b, 10);

      assoc_2d["k"][1] = 10;
      b = cls.get_val_set_2(assoc_2d["k"][1]);
      `checkd(assoc_2d["k"][1], 2);
      `checkd(b, 10);
    end

    begin
      int assoc[int];
      int wild[*];
      int assoc_2d[string][int];
      int assoc_arr[int][3];
      xy_t xy[int];
      xy_t dyn_assoc[][int];
      int queue_assoc[$][int];
      int arr_of_assoc[2][int];
      has_assoc_t has_assoc;
      int with_queue[$];
      int with_found[$];
      int with_assoc[int];
      // Missing element is created also for const ref, and is what the reference refers to
      b = set_get(assoc, 99, assoc[99]);
      `checkd(b, 7);
      `checkd(assoc.num(), 1);
      `checkd(get_val(assoc[next_key()]), 0);
      `checkd(key_calls, 1);
      `checkd(assoc.exists(101), 1);
      `checkd(get_val(wild[8'h9]), 0);
      `checkd(wild.exists(8'h9), 1);
      `checkd(get_val(assoc_2d["m"][4]), 0);
      `checkd(assoc_2d["m"].exists(4), 1);
      `checkd(get_val(assoc_arr[3][2]), 0);
      `checkd(assoc_arr.exists(3), 1);
      `checkd(get_val(xy[5].y), 0);
      `checkd(xy.exists(5), 1);
      `checkd(get_val(cls.m[6]), 0);
      `checkd(cls.m.exists(6), 1);
      `checkd(cls.get_m(7), 0);
      `checkd(cls.m.exists(7), 1);
      dyn_assoc = new[2];
      `checkd(get_val(dyn_assoc[1][8].y), 0);
      `checkd(dyn_assoc[1].exists(8), 1);
      queue_assoc.push_back(assoc);
      `checkd(get_val(queue_assoc[0][9]), 0);
      `checkd(queue_assoc[0].exists(9), 1);
      `checkd(get_val(queue_assoc[$][10]), 0);
      `checkd(queue_assoc[0].exists(10), 1);
      `checkd(get_val(arr_of_assoc[1][11]), 0);
      `checkd(arr_of_assoc[1].exists(11), 1);
      `checkd(get_val(has_assoc.m[12]), 0);
      `checkd(has_assoc.m.exists(12), 1);
      with_queue.push_back(1);
      with_found = with_queue.find_first_index() with (get_val(with_assoc[item]) == 0);
      `checkd(with_found.size(), 1);
      `checkd(with_assoc.exists(1), 1);
      // Not created for a by-value element, only in the copy of a by-value array, and not
      // in a const, const ref or input port array
      `checkd(get_val_input(assoc[50]), 0);
      `checkd(get_elem(assoc, 51), 0);
      `checkd(get_elem_input(assoc, 52), 3);
      `checkd(assoc.exists(50), 0);
      `checkd(assoc.exists(51), 0);
      `checkd(assoc.exists(52), 0);
      `checkd(assoc.num(), 2);
      `checkd(get_val(cls.cm[3]), 0);
      `checkd(cls.cm.exists(3), 0);
      `checkd(sub_i.get_in_elem(3), 0);
      `checkd(in_aa.exists(3), 0);
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
  end

  int cyc = 0;

  // Logic reading the array sees an element created by another process, also through a function
  int seen_assoc[int];
  int seen_num;
  initial seen_assoc[9] = 0;
  always_comb begin
    seen_num = 0;
    foreach (seen_assoc[i]) seen_num = seen_num + 1;
  end
  function automatic int get_seen(input int k);
    return get_val(seen_assoc[k]);
  endfunction

  // Also by an event-controlled process
  int timed_assoc[int];
  int timed_num;
  initial timed_assoc[9] = 0;
  always_comb begin
    timed_num = 0;
    foreach (timed_assoc[i]) timed_num = timed_num + 1;
  end
  always begin
    @(posedge clk);
    if (cyc == 2) `checkd(get_val(timed_assoc[0]), 0);
  end

  // Also by level-sensitive and event-triggered processes, which are not combinational logic
  int trig_assoc[int];
  event trig_ev;
  always @(cyc) if (cyc == 2) `checkd(get_val(trig_assoc[0]), 0);
  always @(trig_ev) `checkd(get_val(trig_assoc[1]), 0);

  // Also for an array an always_ff writes
  int ff_assoc[int];
  always_ff @(posedge clk) ff_assoc[0] = cyc;

  always @(posedge clk) begin
    cyc <= cyc + 1;
    if (cyc == 1) begin
      `checkd(seen_num, 1);
      `checkd(get_val(seen_assoc[0]), 0);
    end
    if (cyc == 2) begin
      `checkd(seen_num, 2);
      `checkd(get_seen(1), 0);
    end
    if (cyc == 4) `checkd(timed_num, 2);
    if (cyc == 2) ->trig_ev;
    if (cyc == 5) `checkd(trig_assoc.num(), 2);
    if (cyc == 1) `checkd(get_val(ff_assoc[5]), 0);
    if (cyc == 2) `checkd(ff_assoc.exists(5), 1);
    if (cyc == 6) begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
