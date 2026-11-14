// DESCRIPTION: Verilator: Tristate nets with a net delay
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0x exp=%0x (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

module drv (
    inout wire io,
    input en,
    input d
);
  assign io = en ? d : 1'bz;
endmodule

module drv_dly (
    io,
    en
);
  inout io;
  input en;
  // A net delay on the net of a port
  wire #20 io;
  assign io = en ? 1'b1 : 1'bz;
endmodule

interface bus_if;
  tri #20 data;
endinterface

module drv_if (
    bus_if b,
    input en
);
  assign b.data = en ? 1'b1 : 1'bz;
endmodule

module t;
  logic en1 = 0;
  logic en2 = 0;
  logic d = 1;

  // A net delay applies to the resolved value of all drivers (IEEE 1800-2023 28.16)
  tri #20 w_tri;
  assign w_tri = en1 ? d : 1'bz;
  assign w_tri = en2 ? ~d : 1'bz;

  // The delay of a driver adds to the net delay (IEEE 1800-2023 10.3.3)
  wire #20 w_dly;
  assign #10 w_dly = en1 ? d : 1'bz;
  assign w_dly = en2 ? ~d : 1'bz;

  tri1 #20 w_pull;
  assign w_pull = en1 ? 1'b0 : 1'bz;

  wire #30 w_port;
  drv u_drv1 (
      .io(w_port),
      .en(en1),
      .d(d)
  );
  drv u_drv2 (
      .io(w_port),
      .en(en2),
      .d(~d)
  );

  wire [3:0] #20 w_sel;
  assign w_sel[1:0] = en1 ? 2'b10 : 2'bz;
  assign w_sel[3:2] = en1 ? 2'b11 : 2'bz;
  assign w_sel[1:0] = en2 ? 2'b00 : 2'bz;
  assign w_sel[3:2] = en2 ? 2'b01 : 2'bz;

  // Changes to and from z are delayed, and a pulse shorter than the delay is filtered
  logic z_en = 0;
  tri #20 w_z;
  assign w_z = z_en ? 1'b1 : 1'bz;
  tri1 #20 w_release;
  assign w_release = z_en ? 1'b0 : 1'bz;
  wire w_sub;
  drv_dly u_drv_dly (
      .io(w_sub),
      .en(z_en)
  );
  bus_if bus ();
  drv_if u_drv_if (
      .b(bus),
      .en(z_en)
  );
  initial begin
    #50;
    `checkh(w_z === 1'bz, 1'b1);
    `checkh(w_release, 1'b1);
    `checkh(w_sub === 1'bz, 1'b1);
    `checkh(bus.data === 1'bz, 1'b1);
    z_en = 1;
    #5;  // 55
    `checkh(w_z === 1'bz, 1'b1);
    `checkh(w_release, 1'b1);
    `checkh(w_sub === 1'bz, 1'b1);
    `checkh(bus.data === 1'bz, 1'b1);
    #20;  // 75
    `checkh(w_z, 1'b1);
    `checkh(w_release, 1'b0);
    `checkh(w_sub, 1'b1);
    `checkh(bus.data, 1'b1);
    z_en = 0;
    #5;  // 80
    `checkh(w_z, 1'b1);
    `checkh(w_release, 1'b0);
    `checkh(w_sub, 1'b1);
    `checkh(bus.data, 1'b1);
    #20;  // 100
    `checkh(w_z === 1'bz, 1'b1);
    `checkh(w_release, 1'b1);
    `checkh(w_sub === 1'bz, 1'b1);
    `checkh(bus.data === 1'bz, 1'b1);
    z_en = 1;
    #5;  // 105
    z_en = 0;
    #10;  // 115
    `checkh(w_z === 1'bz, 1'b1);
    #20;  // 135
    `checkh(w_z === 1'bz, 1'b1);
    `checkh(w_release, 1'b1);
    `checkh(bus.data === 1'bz, 1'b1);
  end

  // A data change then an enable change within the delay: the pending value is replaced
  logic h_en = 1;
  logic h_d = 1;
  tri #20 w_handoff;
  assign w_handoff = h_en ? h_d : 1'bz;
  initial begin
    #50;
    h_d = 0;
    #5;  // 55
    h_en = 0;
    #17;  // 72
    `checkh(w_handoff, 1'b1);
    #8;  // 80
    `checkh(w_handoff === 1'bz, 1'b1);
  end

  initial begin
    en2 = 1;
    #90;
    `checkh(w_tri, 1'b0);
    `checkh(w_dly, 1'b0);
    `checkh(w_pull, 1'b1);
    `checkh(w_port, 1'b0);
    `checkh(w_sel, 4'b0100);
    #10;  // 100
    en2 = 0;
    en1 = 1;
    #15;  // 115
    `checkh(w_tri, 1'b0);
    `checkh(w_dly, 1'b0);
    `checkh(w_pull, 1'b1);
    `checkh(w_port, 1'b0);
    `checkh(w_sel, 4'b0100);
    #10;  // 125
    `checkh(w_tri, 1'b1);
    `checkh(w_pull, 1'b0);
    `checkh(w_port, 1'b0);
    `checkh(w_sel, 4'b1110);
    #10;  // 135
    `checkh(w_dly, 1'b1);
    `checkh(w_port, 1'b1);
    #10;  // 145
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
