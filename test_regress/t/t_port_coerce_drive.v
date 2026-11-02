// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// A written input net port that is not coerced to inout drives the net
// connected to it if that net has no other driver, as the port and the net
// collapse into one net (IEEE 1800-2023 23.3.3.7)

// verilator lint_off ASSIGNIN

typedef struct packed {
  int DW;
  int CW;
} cfg_t;

// Agent interface, written through a virtual interface, directly or by a
// clocking block
interface dvc_if #(
    parameter cfg_t CFG = '{DW: 8, CW: 2}
) (
    input logic [CFG.DW-1:0] data,
    input logic valid,
    input logic [CFG.CW-1:0] credit,
    input logic credit_valid,
    input logic clk
);
  clocking tx_cb @(posedge clk);
    output data;
    output valid;
    input credit;
  endclocking
  clocking rx_cb @(posedge clk);
    input data;
    input valid;
    output credit;
    output credit_valid;
  endclocking
endinterface

interface pif (
    input logic v
);
endinterface

interface pif2 (
    input logic [1:0] v
);
endinterface

// Driven only by a clocking block
interface cb_if (
    input logic clk,
    input logic d
);
  clocking cb @(posedge clk);
    output d;
  endclocking
endinterface

interface var_if (
    input var logic v
);
endinterface

// Written inside the interface
interface iif (
    input logic v
);
  task set(logic val);
    v = val;
  endtask
endinterface

module core (
    input clk,
    input logic [7:0] in_data[2][2],
    input logic in_valid[2][2],
    output logic [1:0] in_credit[2][2],
    output logic [7:0] out_data[2],
    output logic out_valid[2],
    input logic [1:0] out_credit[2],
    input logic out_credit_valid[2],
    input logic in_cb,
    output logic [7:0] sum
);
  always_ff @(posedge clk) begin
    automatic logic [7:0] s = 0;
    for (int i = 0; i < 2; i++) begin
      for (int j = 0; j < 2; j++) begin
        if (in_valid[i][j]) s += in_data[i][j];
      end
    end
    sum <= s;
  end
  for (genvar i = 0; i < 2; i++) begin : g_i
    for (genvar j = 0; j < 2; j++) begin : g_j
      assign in_credit[i][j] = {in_valid[i][j], 1'b1};
    end
  end
  for (genvar k = 0; k < 2; k++) begin : g_k
    assign out_data[k] = 8'h40 + 8'(k);
    assign out_valid[k] = out_credit_valid[k] & out_credit[k][0];
  end
endmodule

// The DUT, its inputs left unconnected
module wrapper (
    input clk,
    input logic [7:0] w_in_data[2][2],
    input logic w_in_valid[2][2],
    output logic [1:0] w_in_credit[2][2],
    output logic [7:0] w_out_data[2],
    output logic w_out_valid[2],
    input logic [1:0] w_out_credit[2],
    input logic w_out_credit_valid[2],
    input logic w_in_cb,
    output logic [7:0] sum
);
  core u_core (
      .clk,
      .in_data(w_in_data),
      .in_valid(w_in_valid),
      .in_credit(w_in_credit),
      .out_data(w_out_data),
      .out_valid(w_out_valid),
      .out_credit(w_out_credit),
      .out_credit_valid(w_out_credit_valid),
      .in_cb(w_in_cb),
      .sum
  );
endmodule

// Bound into the DUT, connecting interfaces by hierarchical references:
// transmitting agents into the DUT inputs, receiving agents on the DUT
// outputs, which are not overridden, returning credits into the DUT inputs
module harness;
  virtual dvc_if tx_vifs[2][2];
  virtual dvc_if rx_vifs[2];
  for (genvar i = 0; i < 2; i++) begin : g_i
    for (genvar j = 0; j < 2; j++) begin : g_j
      dvc_if u_tx (
          .data(wrapper.w_in_data[i][j]),
          .valid(wrapper.w_in_valid[i][j]),
          .credit(wrapper.w_in_credit[i][j]),
          .credit_valid(),
          .clk(wrapper.clk)
      );
      initial tx_vifs[i][j] = u_tx;
    end
  end
  for (genvar k = 0; k < 2; k++) begin : g_rx
    dvc_if u_rx (
        .data(wrapper.w_out_data[k]),
        .valid(wrapper.w_out_valid[k]),
        .credit(wrapper.w_out_credit[k]),
        .credit_valid(wrapper.w_out_credit_valid[k]),
        .clk(wrapper.clk)
    );
    initial rx_vifs[k] = u_rx;
  end
  // Clocking block drive through a hierarchical reference connection
  cb_if u_cb (
      .clk(wrapper.clk),
      .d(wrapper.w_in_cb)
  );
endmodule

bind wrapper harness u_h ();

`unconnected_drive pull1
module pulled (
    input logic a,
    output logic q
);
  assign q = a;
endmodule
`nounconnected_drive

module drv_out (
    input logic i,
    output logic o
);
  assign o = i;
endmodule

// Connected to an output port
module osub (
    output wire o
);
  pif u (.v(o));
endmodule

class tx_drv;
  virtual dvc_if vif;
  task send(logic [7:0] d);
    vif.data <= d;
    vif.valid <= 1'b1;
    @(posedge vif.clk);
    vif.valid <= 1'b0;
  endtask
endclass

class rx_drv;
  virtual dvc_if vif;
  task credit(logic [1:0] c);
    vif.credit = c;
    vif.credit_valid <= 1'b1;
  endtask
endclass

module t (
    input wire tin
);
  logic clk = 0;
  always #5 clk = ~clk;

  logic [7:0] sum;
  wrapper u_wrap (
      .clk(clk),
      .w_in_data(),
      .w_in_valid(),
      .w_in_credit(),
      .w_out_data(),
      .w_out_valid(),
      .w_out_credit(),
      .w_out_credit_valid(),
      .w_in_cb(),
      .sum(sum)
  );

  // Plain connection to a local net, written through a virtual interface
  wire wc;
  wire [1:0] wc_cr;
  dvc_if u_c (
      .data(),
      .valid(wc),
      .credit(),
      .credit_valid(),
      .clk(clk)
  );
  pif u_cr (.v(wc_cr[1]));
  // Written by a clocking block and directly, not coerced to inout
  wire wv;
  dvc_if u_dv (
      .data(),
      .valid(wv),
      .credit(),
      .credit_valid(),
      .clk(clk)
  );
  // Interface array, element connections
  wire [1:0] wa;
  pif u_a[1:0] (.v(wa));
  // Written inside the interface
  wire [1:0] wi;
  iif u_i (.v(wi[1]));
  // Written by a hierarchical reference
  wire [1:0] wx;
  pif u_x (.v(wx[0]));
  // Connected to an output port of the parent
  wire wos;
  osub u_os (.o(wos));
  // Forced, so not otherwise driven
  wire wf;
  pif u_f (.v(wf));
  // Disjoint selects
  wire [3:0] pv;
  pif u_pv3 (.v(pv[3]));

  // The following nets have another driver, or are not nets, so are not
  // driven from the port
  logic oi = 1;
  wire wo;
  drv_out u_drv (
      .i(oi),
      .o(wo)
  );
  pif u_o (.v(wo));
  tri1 wt1;
  pif u_t1 (.v(wt1));
  tri0 wt0;
  pif u_t0 (.v(wt0));
  wire wpu;
  pullup (wpu);
  pif u_pu (.v(wpu));
  // Overlapping selects of nets connected to two written ports
  pif2 u_pv10 (.v(pv[1:0]));
  pif u_pv1 (.v(pv[1]));
  wire [7:0] w8;
  pif u_w80 (.v(w8[0]));
  dvc_if u_w8 (
      .data(w8),
      .valid(),
      .credit(),
      .credit_valid(),
      .clk(clk)
  );
  wire ov2[2][2];
  pif u_q00 (.v(ov2[0][0]));
  pif u_q00b (.v(ov2[0][0]));
  pif u_q10 (.v(ov2[1][0]));
  logic pq;
  pulled u_pull (
      .a(),
      .q(pq)
  );
  pif u_p (.v(u_pull.a));
  wire pubw  /*verilator public_flat_rw*/;
  pif u_pub (.v(pubw));
  pif u_tin (.v(tin));
  logic lv = 0;
  dvc_if u_lv (
      .data(),
      .valid(lv),
      .credit(),
      .credit_valid(),
      .clk(clk)
  );
  wire [1:0] idxw;
  logic idx = 1;
  pif u_idx (.v(idxw[idx]));
  wire uw[2];
  initial begin
    if (idx == 0) begin
      force wf = 1'b0;
      release wf;
    end
  end
  pif u_uw (.v(uw[idx]));
  pif u_const (.v(1'b0));
  wire wvar;
  var_if u_var (.v(wvar));
  virtual var_if vvar = u_var;
  pif u_unc (.v());

  initial begin
    automatic tx_drv tx[2][2];
    automatic rx_drv rx[2];
    automatic tx_drv txc = new;
    foreach (tx[i, j]) tx[i][j] = new;
    foreach (rx[k]) rx[k] = new;
    txc.vif = u_c;
    @(posedge clk);
    foreach (tx[i, j]) tx[i][j].vif = u_wrap.u_h.tx_vifs[i][j];
    foreach (rx[k]) rx[k].vif = u_wrap.u_h.rx_vifs[k];
    fork
      tx[0][1].send(8'h11);
      tx[1][0].send(8'h22);
      txc.send(8'h33);
    join
    #1;
    `checkh(sum, 8'h33);
    `checkh(u_wrap.w_in_valid[0][1], 1'b0);
    `checkh(u_wrap.w_in_credit[0][1], 2'b01);
    `checkh(tx[0][1].vif.credit, 2'b01);
    `checkh(rx[1].vif.data, 8'h41);
    `checkh(rx[1].vif.valid, 1'b0);
    rx[1].credit(2'b11);
    tx[1][1].send(8'h44);
    #1;
    `checkh(sum, 8'h44);
    `checkh(u_wrap.w_out_credit[1], 2'b11);
    `checkh(u_wrap.w_out_credit_valid[1], 1'b1);
    `checkh(rx[1].vif.valid, 1'b1);
    `checkh(rx[0].vif.valid, 1'b0);

    txc.vif.valid <= 1'b1;
    u_cr.v = 1'b1;
    u_wrap.u_h.u_cb.cb.d <= 1'b1;
    u_dv.tx_cb.valid <= 1'b1;
    u_a[0].v = 1'b1;
    u_a[1].v <= 1'b0;
    u_i.set(1'b1);
    u_x.v = 1'b1;
    u_os.u.v = 1'b1;
    u_f.v = 1'b1;
    u_pv3.v = 1'b1;
    u_pv10.v = 2'b11;
    u_pv1.v = 1'b1;
    u_w8.data = 8'hff;
    u_w80.v = 1'b1;
    u_q00.v = 1'b1;
    u_q00b.v = 1'b1;
    u_t1.v = 1'b0;
    u_t0.v = 1'b1;
    u_q10.v = 1'b1;
    u_pu.v = 1'b0;
    u_o.v = 1'b0;
    u_p.v = 1'b0;
    u_pub.v = 1'b1;
    u_tin.v = 1'b1;
    u_lv.valid = 1'b1;
    u_idx.v = 1'b1;
    u_uw.v = 1'b1;
    u_const.v = 1'b1;
    u_unc.v = 1'b1;
    vvar.v = 1'b1;
    repeat (2) @(posedge clk);
    `checkh(wc, 1'b1);
    `checkh(wc_cr[1], 1'b1);
    `checkh(u_wrap.w_in_cb, 1'b1);
    `checkh(u_wrap.u_core.in_cb, 1'b1);
    `checkh(wv, 1'b1);
    `checkh(wa, 2'b01);
    `checkh(wi[1], 1'b1);
    `checkh(wx[0], 1'b1);
    `checkh(wos, 1'b1);
    `checkh(wf, 1'b1);
    `checkh(pv[3], 1'b1);
    if (pv[1:0] === 2'b11) `stop;
    if (w8 === 8'hff) `stop;
    if (ov2[0][0] === 1'b1) `stop;
    `checkh(wt1, 1'b1);
    `checkh(wt0, 1'b0);
    if (ov2[1][0] !== 1'b1) `stop;
    `checkh(wpu, 1'b1);
    `checkh(wo, 1'b1);
    `checkh(pq, 1'b1);
    `checkh(pubw, 1'bz);
    `checkh(lv, 1'b0);
    `checkh(idxw, 2'bzz);
    if (uw[1] === 1'b1) `stop;
    `checkh(wvar, 1'bz);
    u_dv.valid = 1'b0;
    u_i.set(1'b0);
    u_x.v <= 1'b0;
    oi = 0;
    #1;
    `checkh(wo, 1'b0);
    oi = 1;
    #1;
    `checkh(wo, 1'b1);
    `checkh(wv, 1'b0);
    `checkh(wi[1], 1'b0);
    `checkh(wx[0], 1'b0);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
