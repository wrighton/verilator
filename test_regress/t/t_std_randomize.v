// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2025 PlanV GmbH
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop;
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define checks(gotv,expv) do if ((gotv) != (expv)) begin $write("%%Error: %s:%0d:  got='%s' exp='%s'\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

class std_randomize_class;

  rand bit [7:0] addr;
  rand bit [31:0] data;
  rand bit [63:0] data_x_4;

  bit [7:0] old_addr;
  bit [31:0] old_data;
  bit [63:0] old_data_x_4;

  function void std_randomize();
    int success;
    bit valid;

    old_addr = addr;
    old_data = data;
    old_data_x_4 = data_x_4;

    success = std::randomize(addr, data);

    valid = (success == 1) && !(addr == old_addr || data == old_data) && data_x_4 == old_data_x_4;

    `checkd(valid, 1);
  endfunction

endclass

parameter int PARAM = 123;

typedef struct {
  bit [63:0] vpn;
  bit is_valid;
} page_t;

typedef struct {
  rand bit [63:0] vpn;
  rand bit is_valid;
  bit [7:0] tag;
} rpage_t;

typedef struct {
  bit [63:0] base;
  bit en;
} cfg_t;

typedef struct {
  rand bit b1;
  rand bit [6:0] b7;
  rand int i32;
  rand bit [63:0] q64;
  rand bit [94:0] w95;
  rand rpage_t page;
  rand bit [14:0] arr[3:1];
  rand rpage_t pages[2];
  rand bit [6:0] q7[$];
  rand struct packed {
    bit [3:0] hi;
    bit [2:0] lo;
  } pk;
  int keep_i;
  cfg_t plain;
  rpage_t norand;
  string name;
} mixed_t;

class std_randomize_struct_class;
  page_t page;

  function int make_page();
    return std::randomize(page) with {
      page.vpn inside {[8:15]};
      page.is_valid == 1;
    };
  endfunction

  function int make_page_dist();
    return std::randomize(page) with { page.vpn dist {20 := 1, 30 := 1}; };
  endfunction
endclass

module t_scope_std_randomize;
  bit [7:0] addr;
  bit [15:0] data;
  int limit[10];
  bit [6:0] limit_7bits[10];
  bit [14:0] limit_15bits[10];
  bit [30:0] limit_31bits[10];
  bit [62:0] limit_63bits[10];
  bit [94:0] limit_95bits[10];
  int x;
  int y = 50;
  int arr1[2];
  int arr2[2];
  mixed_t mixed;

  // Unpacked struct arguments: only rand members and members the constraints name change
  task automatic test_struct();
    mixed_t prev;
    page_t page;
    page_t prev_page;
    int x;
    int ok;
    int changes[12] = '{default: 0};
    int seen_dist[2] = '{0, 0};
    int q7_max = 0;
    bit [6:0] tq[$];
    page_t pn[2];
    rpage_t pq[$];
    rpage_t pr[0:3];
    rpage_t prev_pq[$];
    rpage_t prev_pr[0:3];
    std_randomize_struct_class gen = new;
    mixed.keep_i = 42;
    mixed.plain = '{64'h55, 1};
    mixed.norand.vpn = 64'h77;
    mixed.page.tag = 8'h5a;
    mixed.pages[1].tag = 8'ha5;
    mixed.name = "keep";
    repeat (4) mixed.q7.push_back(0);
    repeat (3) pq.push_back('{0, 0, 8'h3c});
    pr[3].tag = 8'hc3;
    repeat (4) tq.push_back(0);
    pn[1] = '{64'h99, 1};
    repeat (20) begin
      prev = mixed;
      ok = std::randomize(mixed);
      `checkd(ok, 1);
      if (mixed.b1 != prev.b1) ++changes[0];
      if (mixed.b7 != prev.b7) ++changes[1];
      if (mixed.i32 != prev.i32) ++changes[2];
      if (mixed.q64 != prev.q64) ++changes[3];
      if (mixed.w95 != prev.w95) ++changes[4];
      if (mixed.page.vpn != prev.page.vpn) ++changes[5];
      if (mixed.arr[1] != prev.arr[1] && mixed.arr[3] != prev.arr[3]) ++changes[6];
      if (mixed.pages[0].vpn != prev.pages[0].vpn && mixed.pages[1].vpn != prev.pages[1].vpn)
        ++changes[7];
      if (mixed.q7[0] != prev.q7[0] && mixed.q7[3] != prev.q7[3]) ++changes[8];
      if (mixed.pk != prev.pk) ++changes[11];
      foreach (mixed.q7[i]) if (int'(mixed.q7[i]) > q7_max) q7_max = int'(mixed.q7[i]);
      `checkh(mixed.page.tag, 8'h5a);
      `checkh(mixed.pages[1].tag, 8'ha5);
      `checkd(mixed.keep_i, prev.keep_i);
      `checkh(mixed.plain.base, prev.plain.base);
      `checkd(mixed.plain.en, 1);
      `checkh(mixed.norand.vpn, 64'h77);
      `checks(mixed.name, "keep");

      prev_pq = pq;
      prev_pr = pr;
      ok = std::randomize(pq, pr, tq, pn);
      `checkd(ok, 1);
      if (pq[0].vpn != prev_pq[0].vpn && pq[2].vpn != prev_pq[2].vpn) ++changes[9];
      if (pr[0].vpn != prev_pr[0].vpn && pr[3].vpn != prev_pr[3].vpn) ++changes[10];
      `checkh(pq[2].tag, 8'h3c);
      `checkh(pr[3].tag, 8'hc3);
      foreach (tq[i]) if (int'(tq[i]) > q7_max) q7_max = int'(tq[i]);
      `checkh(pn[1].vpn, 64'h99);
      `checkd(pn[1].is_valid, 1);

      ok = std::randomize(mixed, x) with {
        mixed.page.vpn < 64'd100;
        mixed.w95 > 95'h1_0000_0000_0000_0000;
        mixed.w95 < 95'h1_0000_0000_0000_0010;
        mixed.pages[1].is_valid == 1;
        mixed.keep_i inside {[1:5]};
        mixed.plain.base inside {[100:110]};
        x == int'(mixed.b7) + 1;
      };
      `checkd(ok, 1);
      if (mixed.page.vpn >= 64'd100) `stop;
      if (mixed.w95 <= 95'h1_0000_0000_0000_0000 || mixed.w95 >= 95'h1_0000_0000_0000_0010) `stop;
      `checkd(mixed.pages[1].is_valid, 1);
      if (mixed.keep_i < 1 || mixed.keep_i > 5) `stop;
      `checkd(x, int'(mixed.b7) + 1);
      if (mixed.plain.base < 100 || mixed.plain.base > 110) `stop;
      `checkd(mixed.plain.en, 1);
      `checkh(mixed.norand.vpn, 64'h77);

      // No rand members and no constraints: nothing changes
      prev_page = page;
      ok = std::randomize(page);
      `checkd(ok, 1);
      `checkh(page.vpn, prev_page.vpn);

      ok = gen.make_page();
      `checkd(ok, 1);
      if (gen.page.vpn < 8 || gen.page.vpn > 15) `stop;
      `checkd(gen.page.is_valid, 1);
      ok = gen.make_page_dist();
      `checkd(ok, 1);
      if (gen.page.vpn == 20) ++seen_dist[0];
      else if (gen.page.vpn == 30) ++seen_dist[1];
      else `stop;
      page = gen.page;
    end
    foreach (changes[i]) if (changes[i] == 0) `stop;
    if (q7_max == 0 || q7_max > 127) `stop;
    if (seen_dist[0] == 0 || seen_dist[1] == 0) `stop;
  endtask

  function bit run();
    int ready;
    int success;

    bit [7:0] old_addr;
    bit [15:0] old_data;
    int old_ready;

    old_addr = addr;
    old_data = data;
    old_ready = ready;
    success = randomize(addr, ready);  // std::randomize
    if (success == 0) return 0;
    if (addr == old_addr && data != old_data && ready == old_ready) begin
      return 0;
    end
    return 1;
  endfunction

  std_randomize_class test;

  initial begin
    int randomize_result;

    // Test class member randomization
    test = new();
    test.old_addr = test.addr;
    test.old_data = test.data;
    test.old_data_x_4 = test.data_x_4;
    randomize_result = std::randomize(test.addr, test.data);
    `checkd(randomize_result, 1);
    if (test.addr == test.old_addr && test.data == test.old_data) $stop;
    `checkd(test.data_x_4, test.old_data_x_4);

    // Test function-based randomization
    `checkd(run(), 1);
    test.std_randomize();

    // Test array randomization with constraints
    randomize_result = std::randomize(limit) with { foreach (limit[i]) { limit[i] < 32'd100;}};
    `checkd(randomize_result, 1);
    foreach (limit[i]) if (limit[i] >= 32'd100) $stop;

    randomize_result = std::randomize(limit_7bits) with { foreach (limit_7bits[i]) { limit_7bits[i] < 7'd10;}};
    `checkd(randomize_result, 1);
    foreach (limit_7bits[i]) if (limit_7bits[i] >= 7'd10) $stop;

    randomize_result = std::randomize(limit_15bits) with { foreach (limit_15bits[i]) { limit_15bits[i] < 15'd1000;}};
    `checkd(randomize_result, 1);
    foreach (limit_15bits[i]) if (limit_15bits[i] >= 15'd1000) $stop;

    randomize_result = std::randomize(limit_31bits) with { foreach (limit_31bits[i]) { limit_31bits[i] < 31'd100000;}};
    `checkd(randomize_result, 1);
    foreach (limit_31bits[i]) if (limit_31bits[i] >= 31'd100000) $stop;

    randomize_result = std::randomize(limit_63bits) with { foreach (limit_63bits[i]) { limit_63bits[i] < 63'd10000000000;}};
    `checkd(randomize_result, 1);
    foreach (limit_63bits[i]) if (limit_63bits[i] >= 63'd10000000000) $stop;

    randomize_result = std::randomize(limit_95bits) with { foreach (limit_95bits[i]) { limit_95bits[i] < 95'd1000000000000;}};
    `checkd(randomize_result, 1);
    foreach (limit_95bits[i]) if (limit_95bits[i] >= 95'd1000000000000) $stop;

    foreach (limit_63bits[i]) begin
      randomize_result = std::randomize(limit_63bits[i]) with { limit_63bits[i] >= 63'd50; limit_63bits[i] < 63'd100;};
      `checkd(randomize_result, 1);
      if ((limit_63bits[i] < 63'd50) || (limit_63bits[i] >= 63'd100)) `stop;
    end

    foreach (limit_95bits[i]) begin
      randomize_result = std::randomize(limit_95bits[i]) with { limit_95bits[i] >= 95'd50; limit_95bits[i] < 95'd1000;};
      `checkd(randomize_result, 1);
      if (limit_95bits[i] < 95'd50 || limit_95bits[i] >= 95'd1000) $stop;
    end

    // Test mixed argument types (VarRef + MemberSel + ArraySel) with interdependent constraints
    randomize_result = std::randomize(addr, test.addr, limit_31bits[0]) with {
      addr > 8'd10; addr < 8'd50;
      test.addr > addr; test.addr < 8'd100;
      limit_31bits[0] > 31'(test.addr); limit_31bits[0] < 31'd200;
    };
    `checkd(randomize_result, 1);
    if (addr <= 8'd10 || addr >= 8'd50) `stop;
    if (test.addr <= addr || test.addr >= 8'd100) `stop;
    if (limit_31bits[0] <= 31'(test.addr) || limit_31bits[0] >= 31'd200) `stop;

    // Test parameter in with clause
    void'(std::randomize(x) with { x > PARAM; });
    if (x <= PARAM) $stop;
    void'(std::randomize(x) with { x < PARAM; x > y; });
    if (x >= PARAM || x <= y) $stop;

    arr1[0] = 1000;
    arr2[0] = 42;
    void'(std::randomize(arr1[0]) with { arr1[0] == arr2[0]; });
    if (arr1[0] != 42) $stop;

    test_struct();

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
