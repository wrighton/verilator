// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv, expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0x exp=%0x (%s !== %s)\n", `__FILE__, `__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

module t (
    input clk
);

  int cyc = 0;
  wire collide = cyc[0];

  // Procedural z assignments to unpacked array elements
  logic [3:0] pipe[2];
  logic [6:0] mem[3:1];
  always @(posedge clk) begin
    pipe[0] <= collide ? 4'bz : 4'(cyc);
    pipe[1] = 'z;
    mem[2] = 7'h55;
    mem[2][2:1] = 2'bz;
  end

  // To elements of other unpacked containers, and members of structures and objects
  class Cls;
    logic [6:0] m;
  endclass
  typedef struct {logic [6:0] m;} st_t;
  logic [6:0] amem[int];
  logic [6:0] wmem[*];
  logic [6:0] qmem[$];
  logic [6:0] dmem[];
  st_t st;
  Cls obj;
  initial begin
    qmem.push_back(0);
    dmem = new[1];
    obj = new;
  end
  always @(posedge clk) begin
    amem[cyc] = 7'h55;
    amem[cyc][2:1] = 2'bz;
    wmem[cyc] = 7'h55;
    wmem[cyc][2:1] = 2'bz;
    qmem[0] = 7'h55;
    qmem[0][2:1] = 2'bz;
    dmem[0] = 7'h55;
    dmem[0][2:1] = 2'bz;
    st.m = 7'h55;
    st.m[2:1] = 2'bz;
    obj.m = 7'h55;
    obj.m[2:1] = 2'bz;
  end

  always @(posedge clk) begin
    cyc <= cyc + 1;
    if (cyc > 1) begin
      // Written on the previous cycle, when collide was inverted
      if (collide) `checkh(pipe[0], 4'(cyc - 1));
      `checkh(mem[2][6:3], 4'b1010);
      `checkh(mem[2][0], 1'b1);
      `checkh({amem[cyc-1][6:3], amem[cyc-1][0]}, 5'b10101);
      `checkh({wmem[cyc-1][6:3], wmem[cyc-1][0]}, 5'b10101);
      `checkh({qmem[0][6:3], qmem[0][0]}, 5'b10101);
      `checkh({dmem[0][6:3], dmem[0][0]}, 5'b10101);
      `checkh({st.m[6:3], st.m[0]}, 5'b10101);
      `checkh({obj.m[6:3], obj.m[0]}, 5'b10101);
    end
    if (cyc == 9) begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
