// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2020 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0)
// verilog_format: on

module t (
    input clk
);

  parameter int sliceddn[4:-3] = '{'h100, 'h101, 'h102, 'h103, 'h104, 'h105, 'h106, 'h107};
  parameter int slicedup[-3:4] = '{'h100, 'h101, 'h102, 'h103, 'h104, 'h105, 'h106, 'h107};
  int alldn[7:0];
  int allup[0:7];
  int twodn[1:0];
  int twoup[0:1];

  initial begin
    `checkh(sliceddn[4], 'h100);
    alldn[7:0] = sliceddn[4:-3];
    `checkh(alldn[7], 'h100);
    alldn[7:0] = sliceddn[-3+:8];  // down: lsb/lo +: width
    `checkh(alldn[7], 'h100);
    alldn[7:0] = sliceddn[4-:8];  // down: msb/hi -: width
    `checkh(alldn[7], 'h100);
    twodn[1:0] = sliceddn[3:2];
    `checkh(twodn[1], 'h101);
    `checkh(twodn[0], 'h102);
    twodn[1:0] = sliceddn[1+:2];
    `checkh(twodn[1], 'h102);
    `checkh(twodn[0], 'h103);
    twodn[1:0] = sliceddn[1-:2];
    `checkh(twodn[1], 'h103);
    `checkh(twodn[0], 'h104);

    `checkh(slicedup[4], 'h107);
    allup[0:7] = slicedup[-3:4];
    `checkh(alldn[7], 'h100);
    allup[0:7] = slicedup[-3+:8];  // up: msb/lo +: width
    `checkh(alldn[7], 'h100);
    allup[0:7] = slicedup[4-:8];  // up: lsb/hi -: width
    `checkh(alldn[7], 'h100);
    twoup[0:1] = slicedup[2:3];
    `checkh(twoup[1], 'h106);
    `checkh(twoup[0], 'h105);
    twoup[0:1] = slicedup[1+:2];
    `checkh(twoup[1], 'h105);
    `checkh(twoup[0], 'h104);
    twoup[0:1] = slicedup[1-:2];
    `checkh(twoup[1], 'h104);
    `checkh(twoup[0], 'h103);

  end

  // The right side is read before writing the left side when they overlap
  class SliceC;
    int arr[0:4];
    static function void shift(ref int x[0:4], const ref int y[0:4]);
      x[1:3] = y[0:2];
    endfunction
  endclass
  initial begin
    int up[0:4];
    int dn[4:0];
    int rows[3][2];
    int pair[2];
    int big[300];
    SliceC c1;
    SliceC c2;
    int dyn[][1:3];
    int que[$][1:3];
    int asc[string][1:3];

    up = '{1, 2, 3, 4, 5};
    up[1:3] = up[0:2];
    `checkh(up[1], 'h1);
    `checkh(up[2], 'h2);
    `checkh(up[3], 'h3);
    `checkh(up[4], 'h5);
    up = '{1, 2, 3, 4, 5};
    up = {up[1:4], up[0]};
    `checkh(up[0], 'h2);
    `checkh(up[4], 'h1);
    dn = '{5, 4, 3, 2, 1};
    dn[3:1] = dn[2:0];
    `checkh(dn[3], 'h3);
    `checkh(dn[1], 'h1);
    rows = '{'{1, 2}, '{3, 4}, '{5, 6}};
    rows[1:2] = rows[0:1];
    `checkh(rows[2][0], 'h3);
    `checkh(rows[1][1], 'h2);
    rows = '{rows[2], rows[1], rows[0]};
    `checkh(rows[0][0], 'h3);
    `checkh(rows[2][0], 'h1);
    pair = '{7, 8};
    pair = '{pair[1], pair[0]};
    `checkh(pair[0], 'h8);
    `checkh(pair[1], 'h7);
    foreach (big[i]) big[i] = i;
    big[1:299] = big[0:298];
    `checkh(big[1], 'h0);
    `checkh(big[299], 'd298);
    // Through another handle of the same object
    c1 = new;
    c2 = c1;
    c1.arr = '{1, 2, 3, 4, 5};
    c1.arr[1:3] = c2.arr[0:2];
    `checkh(c1.arr[2], 'h2);
    `checkh(c1.arr[3], 'h3);
    // Through 'ref' arguments of the same array
    up = '{1, 2, 3, 4, 5};
    SliceC::shift(up, up);
    `checkh(up[2], 'h2);
    `checkh(up[3], 'h3);
    // An element of a dynamic, queue or associative array (where expanding an element write
    // can warn of side effects)
    dyn = new[1];
    dyn[0] = '{1, 5, 2};
    dyn[0] = '{dyn[0][3], dyn[0][2], dyn[0][1]};
    `checkh(dyn[0][1], 'h2);
    `checkh(dyn[0][3], 'h1);
    // verilator lint_off SIDEEFFECT
    que.push_back('{1, 5, 2});
    que[0] = '{que[0][3], que[0][2], que[0][1]};
    `checkh(que[0][1], 'h2);
    `checkh(que[0][3], 'h1);
    asc["a"] = '{1, 5, 2};
    asc["a"] = '{asc["a"][3], asc["a"][2], asc["a"][1]};
    // verilator lint_on SIDEEFFECT
    `checkh(asc["a"][1], 'h2);
    `checkh(asc["a"][3], 'h1);
  end

  int nbaup[0:3];
  int nbadn[6:1];
  int nbasrc[3:0];
  int cyc = 0;
  always @(posedge clk) begin
    cyc <= cyc + 1;
    if (cyc == 0) begin
      nbaup = '{1, 2, 3, 4};
      nbadn[4:1] = nbaup;  // Reversed direction
      `checkh(nbadn[4], 'h1);
      `checkh(nbadn[1], 'h4);
      nbadn[6:5] <= nbaup[2:3];
    end
    if (cyc == 1) begin
      `checkh(nbadn[6], 'h3);
      `checkh(nbadn[5], 'h4);
      nbasrc[3:2] <= nbadn[6:5];
    end
    if (cyc == 2) begin
      `checkh(nbasrc[3], 'h3);
      `checkh(nbasrc[2], 'h4);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end

  // Continuous assignments of the elements settle to the values of the whole assignment
  logic [6:0] contsrc;
  // verilator lint_off UNOPTFLAT
  wire [6:0] cont[1:4];
  // verilator lint_on UNOPTFLAT
  assign contsrc = 7'(cyc + 5);
  assign cont[1] = contsrc;
  assign cont[2:4] = cont[1:3];
  always @(posedge clk) begin
    `checkh(cont[2], 7'(cyc + 5));
    `checkh(cont[4], 7'(cyc + 5));
  end

endmodule
