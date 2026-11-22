// DESCRIPTION: Verilator: Readers of public read-write variables in the input
// combinational logic, evaluated on every evaluation, or only when a variable changed with
// -fico-public-change-detect
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

`define STRINGIFY(x) `"x`"

class Counter;
  int value;
  static int total;
  static function void bump();
    total = total + 1;
  endfunction
endclass

class Named;
  string name;
  function void grow();
    name = {name, "x"};
  endfunction
endclass

class Writer;
  static function void set(ref int value, input int newValue);
    value = newValue;
  endfunction
endclass

typedef struct packed {
  logic [40:0] hi;
  logic [53:0] lo;
} wide_t;

module t (
    input clk,
    input int in,
    input int inIco,
    input bit inPlusArg,
    input int pubIn  /*verilator public_flat_rw*/,
    input bit kick,
    input bit kick2,
    output int pubOut  /*verilator public_flat_rw*/,
    output int obsOut,
    input int pubWr  /*verilator public_flat_rw*/,
    output int obsWr,
    output int obsIn,
    output int obsPub,
    output int obsPub2,
    output int obsPubIn,
    output int obsFlag,
    output int obsHidden,
    output int obsDpi,
    output int obsIco,
    output int obsComb,
    output int obsMix,
    output int obsLast,
    output int obsStale,
    output logic [94:0] obsWide,
    output wide_t obsStruct,
    output int obsForce,
    output logic [63:0] obsReal,
    output int obsArr,
    output int obsBias,
    output int obsBias2,
    output int obsTime,
    output int obsPushed,
    output int unsigned obsRand,
    output int obsPlusArg,
    output int unsigned obsRandRange,
    output int obsDist,
    output int obsPlusValue,
    output int obsSeed,
    output int obsInPlusArg,
    output int obsObj,
    output int obsCyc,
    output int obsStatic,
    output byte obsStamp,
    output int obsFormat,
    output int obsPrinted,
    output bit obsAssert,
    output bit obsEvent,
    output bit obsDeferAction,
    output int obsForceAction,
    output bit [7:0] obsLatch
);
  // Counts the evaluations of a reader. Declared pure, as a reader that is not pure runs on every
  // evaluation.
  import "DPI-C" pure function int count(int which, int value);
  import "DPI-C" function int add_host_bias(int value);
  import "DPI-C" context function void cxx_put_dpi(int value);
  import "DPI-C" context function void cxx_put_ico(int value);
  import "DPI-C" context function void cxx_restore_stale();
  import "DPI-C" context function void cxx_put_mix(int value);
  import "DPI-C" context function void cxx_put_last(int value);

  // Readers of a top level input, and of a public variable, which with change detection run alike,
  // only when it changed
  int pub /*verilator public_flat_rw*/ = 1;
  assign obsIn = count(0, in) * 3 + 1;
  assign obsPub = count(1, pub) * 3 + 1;
  assign obsPub2 = pub + 2;

  assign obsPubIn = pubIn + 1;

  // Public top level ports read by the logic: an output, and an input the design also writes,
  // which neither input nor public variable change detection applies to
  assign pubOut = in + 7;
  assign obsOut = pubOut * 2;
  always @(posedge clk) begin
    /* verilator lint_off ASSIGNIN */
    if (kick2) pubWr = pubWr + 1;
    /* verilator lint_on ASSIGNIN */
  end
  assign obsWr = pubWr * 2;

  // Set by the design, cleared from outside
  int flag /*verilator public_flat_rw*/ = 0;
  always @(posedge clk) flag <= 1;
  assign obsFlag = flag * 3 + 1;

  // Written by a class method, and by C++, after the input combinational logic
  int cyc = 0;
  int pubHidden /*verilator public_flat_rw*/ = 0;
  int pubDpi /*verilator public_flat_rw*/ = 0;
  always @(posedge clk) begin
    cyc <= cyc + 1;
    Writer::set(pubHidden, cyc);
    cxx_put_dpi(cyc);
  end
  assign obsHidden = pubHidden * 3 + 1;
  assign obsDpi = pubDpi * 3 + 1;

  // Written by C++ during the input combinational logic
  int pubIco /*verilator public_flat_rw*/ = 0;
  always @* cxx_put_ico(inIco * 2);
  assign obsIco = pubIco * 3 + 1;

  // Written by the input combinational logic: with change detection, its reader runs once per
  // change
  int pubComb /*verilator public_flat_rw*/;
  always_comb pubComb = in + 3;
  assign obsComb = count(2, pubComb) * 3 + 1;

  // Written by the design, then restored by C++ in the same evaluation, which change detection
  // does not see
  int pubStale /*verilator public_flat_rw*/ = 0;
  always @(posedge clk) pubStale <= 1;
  assign obsStale = pubStale * 3 + 1;
  always @(obsStale) if (obsStale == 4) cxx_restore_stale();

  // Written by the input combinational logic and by C++ during it, which change detection does
  // not see
  int pubMix /*verilator public_flat_rw*/;
  always_comb pubMix = in + 5;
  assign obsMix = pubMix * 3 + 1;
  always @* if (kick) cxx_put_mix(23);

  // Written by C++ during the input combinational logic, then by the design, then restored by C++
  // to the value the input combinational logic saw, which differs from the value at the start
  int pubLast /*verilator public_flat_rw*/ = 0;
  always @* if (kick2) cxx_put_last(2);
  always @(posedge clk) if (kick2) pubLast <= 3;
  assign obsLast = pubLast * 3 + 1;
  always @(obsLast) if (obsLast == 10) cxx_put_last(2);

  // Packed types wider than a word, changes detected in any word
  logic [94:0] pubWide /*verilator public_flat_rw*/ = '0;
  assign obsWide = ~pubWide;
  wide_t pubStruct /*verilator public_flat_rw*/ = '0;
  assign obsStruct = '{hi: pubStruct.hi + 1, lo: pubStruct.lo};

  // Readers of forced, real and unpacked variables, which run on every evaluation
  int pubForce /*verilator forceable*/ /*verilator public_flat_rw*/ = 3;
  assign obsForce = count(3, pubForce);
  real pubReal /*verilator public_flat_rw*/ = 0.0;
  assign obsReal = $realtobits(pubReal);
  int pubArr[3] /*verilator public_flat_rw*/ = '{1, 2, 3};
  assign obsArr = count(4, pubArr[1]);

  // Read by C++ code that is not pure, whose result changes between evaluations while the variable
  // does not, so its reader runs on every evaluation
  int pubBias /*verilator public_flat_rw*/ = 1;
  assign obsBias = add_host_bias(pubBias);

  // The same, through variables other logic computes from it
  int pubBias2 /*verilator public_flat_rw*/ = 2;
  int biasArg /*verilator public_flat_rd*/;
  int biasArg2 /*verilator public_flat_rd*/;
  always_comb begin
    biasArg = pubBias2 + 1;
    biasArg2 = pubBias2 + 2;
  end
  assign obsBias2 = add_host_bias(biasArg) + add_host_bias(biasArg2) + biasArg;

  // Read with the time, so its reader runs when the time advanced
  int pubTime /*verilator public_flat_rw*/ = 5;
  assign obsTime = ($time > 100) ? pubTime : 0;

  // Assertions on public variables, reported each time their logic runs: when their input changed
  // or, as they read it, the time advanced, a deferred one and an immediate one
  logic [3:0] pubOneHot /*verilator public_flat_rw*/ = 4'b0001;
  always_comb begin
    if (($realtime > 0) && !$isunknown(pubOneHot)) begin
      assert #0 ($onehot0(pubOneHot))
      else $warning("pubOneHot is not one-hot: %h", pubOneHot);
    end
  end
  logic [3:0] pubOneHotImm /*verilator public_flat_rw*/ = 4'b0001;
  always_comb begin
    if ($realtime > 0) begin
      assert ($onehot0(pubOneHotImm))
      else $warning("pubOneHotImm is not one-hot: %h", pubOneHotImm);
    end
  end
  // A deferred assertion not reading the time, reported when its input changed
  logic [3:0] pubOneHotNoTime /*verilator public_flat_rw*/ = 4'b0001;
  always_comb begin
    assert #0 ($onehot0(pubOneHotNoTime))
    else $warning("pubOneHotNoTime is not one-hot: %h", pubOneHotNoTime);
  end

  // Pushed to queues of the design each time its logic runs, which is not only an output
  int pubPush /*verilator public_flat_rw*/ = 0;
  int pushedArr[1][$];
  int pushed[$];
  always_comb begin
    pushedArr[0].push_back(pubPush);
    pushed.push_back(pubPush);
    obsPushed = pushedArr[0].size() + pushed.size();
  end

  // Finishing, an output, when a value is set
  int pubFinish /*verilator public_flat_rw*/ = 0;
  always_comb if (pubFinish == 99) $finish;

  // Drawing a random number, and reading the command line, each time its logic runs
  int pubRand /*verilator public_flat_rw*/ = 1;
  always_comb begin
    if (pubRand == 1) obsRand = $urandom();
    else obsRand = 0;
  end
  int pubPlusArg /*verilator public_flat_rw*/ = 1;
  always_comb begin
    if (pubPlusArg == 1) obsPlusArg = $test$plusargs("late_feature") ? 17 : 3;
    else obsPlusArg = 0;
  end
  // The same with the other random number functions and command line reads
  int pubRandArgs /*verilator public_flat_rw*/ = 1;
  always_comb obsRandRange = (pubRandArgs == 1) ? $urandom_range(1000000, 0) : 0;
  always_comb begin
    int seed;
    seed = pubRandArgs;
    obsDist = $dist_uniform(seed, 0, 1000000);
  end
  always_comb begin
    int value;
    value = 0;
    if ((pubRandArgs == 1) && $value$plusargs("late_value=%d", value)) obsPlusValue = value;
    else obsPlusValue = 0;
  end
  always_comb obsSeed = (pubRandArgs == 1) ? $get_initial_random_seed() : 0;
  // The same depending on a top level input only
  always_comb begin
    if (inPlusArg) obsInPlusArg = $test$plusargs("late_input") ? 17 : 3;
    else obsInPlusArg = 0;
  end

  // A member of an object counted by clocked logic, read through its handle each time its logic
  // runs
  int pubObj /*verilator public_flat_rw*/ = 1;
  Counter counter = new;
  always @(posedge clk) counter.value <= counter.value + 1;
  always_comb obsObj = (pubObj == 1) ? counter.value : 0;
  assign obsCyc = cyc;
  // The same with the members of an object formatted with it
  int pubPrinted /*verilator public_flat_rw*/ = 1;
  Named named = new;
  always @(posedge clk) named.grow();
  always_comb begin
    string formatted;
    formatted = $sformatf("%p", named);
    obsPrinted = (pubPrinted == 1) ? formatted.len() : 0;
  end
  // The same with a static member of a class
  int pubStatic /*verilator public_flat_rw*/ = 1;
  always @(posedge clk) Counter::bump();
  always_comb obsStatic = (pubStatic == 1) ? Counter::total : 0;

  // Formatting a time with the $timeformat set by C++ code, each time its logic runs
  time pubStamp /*verilator public_flat_rw*/ = 1;
  export "DPI-C" function choose_format;
  function void choose_format(input bit use_b);
    if (use_b) $timeformat(-9, 0, "B", 0);
    else $timeformat(-9, 0, "A", 0);
  endfunction
  always_comb begin
    string formatted;
    formatted = $sformatf("%0t", pubStamp);
    obsStamp = formatted[formatted.len()-1];
  end

  // Formatting without a time
  int pubFormat /*verilator public_flat_rw*/ = 7;
  always_comb begin
    string formatted;
    formatted = $sformatf("%0d%%t", pubFormat);
    obsFormat = formatted.len();
  end

  // An assertion with an action, controlled by C++ code, each time its logic runs
  int pubAssert /*verilator public_flat_rw*/ = 1;
  always_comb begin
    obsAssert = 1'b0;
    assert (pubAssert != 0) obsAssert = 1'b1;
    else obsAssert = 1'b0;
  end

  // A deferred assertion with an action, and one releasing a force, in their own modules
  t_sched_ico_pubrw_defer_action udefer (.y(obsDeferAction));
  t_sched_ico_pubrw_force_action uforce (.obs(obsForceAction));
  t_sched_ico_pubrw_defer_file ufile ();
  t_sched_ico_pubrw_defer_fatal ufatal ();
  t_sched_ico_pubrw_defer_call ucall ();
  t_sched_ico_pubrw_latch ulatch (.q(obsLatch));

  // Whether an event was triggered, which is cleared after its time slot
  int pubEvent /*verilator public_flat_rw*/ = 1;
  event ev;
  initial -> ev;
  assign obsEvent = (pubEvent != 0) && ev.triggered;

  // Writing to a file each time its logic runs
  int pubFile /*verilator public_flat_rw*/ = 0;
  int fd;
  initial begin
    fd = $fopen({`STRINGIFY(`TEST_OBJ_DIR), "/ico_bytes.out"}, "w");
    if (fd == 0) $fatal(1, "could not open the file");
  end
  always_comb if (pubFile != 0) $fwrite(fd, "%c", pubFile[7:0]);
  final $fclose(fd);
endmodule

// A deferred assertion with an action writing a variable, controlled by C++ code, each time its
// logic runs
module t_sched_ico_pubrw_defer_action (
    output bit y
);
  bit p /*verilator public_flat_rw*/ = 0;
  initial y = 0;
  task automatic set_y();
    y = 1;
  endtask
  always_comb begin
    assert #0 (!p)
    else set_y();
  end
endmodule

// An assertion with an action releasing a force, controlled by C++ code, each time its logic runs
module t_sched_ico_pubrw_force_action (
    output int obs
);
  int gate /*verilator public_flat_rw*/ = 1;
  int base = 1;
  wire [31:0] target = base;
  initial force target = 5;
  always @* begin
    assert (gate != 0)
    else release target;
  end
  assign obs = target;
endmodule

// A deferred assertion writing to a file, its descriptor a variable, each time its logic runs
module t_sched_ico_pubrw_defer_file;
  bit p /*verilator public_flat_rw*/ = 0;
  int fd;
  initial begin
    fd = $fopen({`STRINGIFY(`TEST_OBJ_DIR), "/ico_defer_file.out"}, "w");
    if (fd == 0) $fatal(1, "could not open the file");
  end
  always_comb begin
    assert #0 (!p)
    else $fwrite(fd, "X");
  end
  final $fclose(fd);
endmodule

// A deferred assertion ending the simulation, an output, controlled by C++ code
module t_sched_ico_pubrw_defer_fatal;
  bit p /*verilator public_flat_rw*/ = 0;
  always_comb begin
    assert #0 (!p)
    else $fatal(1, "ufatal p=%0d", p);
  end
endmodule

// A deferred assertion calling C++ code with a variable, each time its logic runs
module t_sched_ico_pubrw_defer_call;
  import "DPI-C" function void cxx_defer_call(input int value);
  bit p /*verilator public_flat_rw*/ = 0;
  int n;
  initial n = $c32("1");
  always_comb begin
    assert #0 (!p)
    else cxx_defer_call(n);
  end
endmodule

// A latch incrementing its own output, which is not an input of it (IEEE 1800-2023 9.2.2.3)
module t_sched_ico_pubrw_latch (
    output bit [7:0] q
);
  bit rst /*verilator public_flat_rw*/ = 1;
  bit p /*verilator public_flat_rw*/ = 0;
  always_latch begin
    if (rst) q = 8'd0;
    if (p) q = q + 8'd1;
  end
endmodule
