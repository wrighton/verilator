// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0x exp=%0x (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// A simple (non-hierarchical) name used as a variable resolves to the variable
// even if a named block of the same name is in an intermediate scope

class Cls;
  int v;
  function int get();
    begin : outer
      begin : v
      end
      begin : deeper
        get = v;
      end
    end
  endfunction
endclass

module t (
    input clk
);
  integer cyc = 0;

  logic set_pte_valid;
  logic [2:0] wr;
  always_comb begin : updates
    wr = '0;
    if (set_pte_valid) begin : set_pte_valid
      wr[0] = set_pte_valid;
    end
    wr[1] = set_pte_valid;
    begin : two_up
      begin : deeper
        wr[2] = set_pte_valid;
      end
    end
  end

  // A hierarchical name still starts at the block
  logic [1:0] hr;
  always_comb begin : hier
    begin : set_pte_valid
      logic inner;
      inner = set_pte_valid;
    end
    hr[0] = set_pte_valid.inner;
    hr[1] = hier.set_pte_valid.inner;
  end

  logic gen_v;
  logic gen_out;
  if (1) begin : g_outer
    if (1) begin : gen_v
      logic unused;
    end
    assign gen_out = ~gen_v;
  end

  logic [1:0] fork_v;
  task automatic set_fork();
    begin : body
      fork : fork_v
        begin
        end
      join
      fork_v = 2'b10;
    end
  endtask

  Cls c = new;

  always @(posedge clk) begin
    cyc <= cyc + 1;
    set_pte_valid <= cyc[0];
    gen_v <= cyc[1];
    c.v = cyc;
    if (cyc == 3) set_fork();
    if (cyc > 1) begin
      `checkh(wr, {3{set_pte_valid}});
      `checkh(hr, {2{set_pte_valid}});
      `checkh(gen_out, ~gen_v);
      `checkd(c.get(), cyc);
    end
    if (cyc == 5) begin
      `checkh(fork_v, 2'b10);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
