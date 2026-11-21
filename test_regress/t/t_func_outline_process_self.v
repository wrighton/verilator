// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Functions with bodies larger than --output-split-cfuncs, calling
// std::process::self() twice and forking a process, get the same process both
// times
class ProcSelf;
  static std::process s_forked;
  static std::process s_forkedDisabled;
  static std::process s_forkedPublic;
  static function void forkSelf();
    fork
      s_forked = std::process::self();
    join_none
  endfunction
  static function void forkDisabled();
    fork
      s_forkedDisabled = std::process::self();
    join_none
  endfunction
  static function void forkPublic();
    fork
      s_forkedPublic = std::process::self();
    join_none
  endfunction
  static function bit run(int x, output int res);
    std::process p1;
    std::process p2;
    automatic int m = x;
    p1 = std::process::self();
    m = m * 3 + 0;
    m ^= m >>> 2;
    m = m * 3 + 1;
    m ^= m >>> 2;
    m = m * 3 + 2;
    m ^= m >>> 2;
    m = m * 3 + 3;
    m ^= m >>> 2;
    m = m * 3 + 4;
    m ^= m >>> 2;
    m = m * 3 + 5;
    m ^= m >>> 2;
    m = m * 3 + 6;
    m ^= m >>> 2;
    m = m * 3 + 7;
    m ^= m >>> 2;
    m = m * 3 + 8;
    m ^= m >>> 2;
    m = m * 3 + 9;
    m ^= m >>> 2;
    m = m * 3 + 10;
    m ^= m >>> 2;
    m = m * 3 + 11;
    m ^= m >>> 2;
    m = m * 3 + 12;
    m ^= m >>> 2;
    m = m * 3 + 13;
    m ^= m >>> 2;
    m = m * 3 + 14;
    m ^= m >>> 2;
    p2 = std::process::self();
    forkSelf();
    res = m;
    return p1 == p2;
  endfunction
  // Also disabling the forked process
  static function bit runDisable(int x, output int res);
    std::process p1;
    std::process p2;
    automatic int m = x;
    p1 = std::process::self();
    m = m * 3 + 0;
    m ^= m >>> 2;
    m = m * 3 + 1;
    m ^= m >>> 2;
    m = m * 3 + 2;
    m ^= m >>> 2;
    m = m * 3 + 3;
    m ^= m >>> 2;
    m = m * 3 + 4;
    m ^= m >>> 2;
    m = m * 3 + 5;
    m ^= m >>> 2;
    m = m * 3 + 6;
    m ^= m >>> 2;
    m = m * 3 + 7;
    m ^= m >>> 2;
    m = m * 3 + 8;
    m ^= m >>> 2;
    m = m * 3 + 9;
    m ^= m >>> 2;
    m = m * 3 + 10;
    m ^= m >>> 2;
    m = m * 3 + 11;
    m ^= m >>> 2;
    m = m * 3 + 12;
    m ^= m >>> 2;
    m = m * 3 + 13;
    m ^= m >>> 2;
    m = m * 3 + 14;
    m ^= m >>> 2;
    p2 = std::process::self();
    forkDisabled();
    disable fork;
    res = m;
    return p1 == p2;
  endfunction
endclass

module t;
  function automatic int mix15(int x);
    for (int k = 0; k < 15; k++) begin
      x = x * 3 + k;
      x ^= x >>> 2;
    end
    return x;
  endfunction

  initial begin
    bit same;
    int res;
    same = ProcSelf::run(7, res);
    `checkd(same, 1'b1);
    `checkd(res, mix15(7));
    #2;
    $write("*-* All Finished *-*\n");
    $finish;
  end

  // In another process, as a process disabling forks also gives one to its callees
  initial begin
    bit same;
    int res;
    same = ProcSelf::runDisable(8, res);
    `checkd(same, 1'b1);
    `checkd(res, mix15(8));
    #1;
    `checkd(ProcSelf::s_forkedDisabled == null, 1'b1);
  end

  // A public function called only from C++
  // verilator lint_off UNOPTPUBLIC
  function automatic int pubproc(int x);
    /* verilator public */
    // verilator lint_on UNOPTPUBLIC
    std::process p1;
    std::process p2;
    automatic int m = x;
    p1 = std::process::self();
    m = m * 3 + 0;
    m ^= m >>> 2;
    m = m * 3 + 1;
    m ^= m >>> 2;
    m = m * 3 + 2;
    m ^= m >>> 2;
    m = m * 3 + 3;
    m ^= m >>> 2;
    m = m * 3 + 4;
    m ^= m >>> 2;
    m = m * 3 + 5;
    m ^= m >>> 2;
    m = m * 3 + 6;
    m ^= m >>> 2;
    m = m * 3 + 7;
    m ^= m >>> 2;
    m = m * 3 + 8;
    m ^= m >>> 2;
    m = m * 3 + 9;
    m ^= m >>> 2;
    m = m * 3 + 10;
    m ^= m >>> 2;
    m = m * 3 + 11;
    m ^= m >>> 2;
    m = m * 3 + 12;
    m ^= m >>> 2;
    m = m * 3 + 13;
    m ^= m >>> 2;
    m = m * 3 + 14;
    m ^= m >>> 2;
    p2 = std::process::self();
    ProcSelf::forkPublic();
    disable fork;
    return p1 == p2 ? m : 0;
  endfunction
`ifdef VERILATOR
  function int viaC(int x);
    /* verilator no_inline_task */
    viaC = $c32("pubproc(", x, ")");
  endfunction
  initial begin
    int res;
    res = viaC(9);
    `checkd(res, mix15(9));
  end
`endif
endmodule
