// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define STRINGIFY(x) `"x`"
// verilog_format: on

class Cls;
  logic [6:0] mem[2][4];
endclass

class Holder;
  logic [6:0] mem[0:2][4];
  task load(string file, bit [1:0] i);
    foreach (mem[r, c]) mem[r][c] = 7'h7f;
    $readmemh(file, this.mem[i]);
  endtask
endclass

module t;
  // Index values known only at run time
  int one;
  int two;
  int three;

  function automatic string path(string name);
    return {`STRINGIFY(`TEST_OBJ_DIR), "/", name};
  endfunction

  task automatic write_file(string name, string text);
    int fd;
    fd = $fopen(path(name), "w");
    $fwrite(fd, text);
    $fclose(fd);
  endtask

  initial begin
    if (!$value$plusargs("one=%d", one)) one = 1;
    if (!$value$plusargs("two=%d", two)) two = 2;
    if (!$value$plusargs("three=%d", three)) three = 3;
    write_file("elem_a.hex", "11\n12\n13\n14\n");
    write_file("elem_b.hex", "21\n22\n23\n24\n25\n26\n");
    write_file("elem_d.hex", "21\n22\n23\n24\n");
    write_file("elem_t.hex", "31\n32\n33\n");
    write_file("elem_c.bin", "1010101\n0101010\n");
    write_file("elem_w.hex", "1_0000_0001\n1_0000_0002\n");

    begin
      // Test: constant index into array of arrays, non-zero and descending bounds
      logic [30:0] mem[3:1][2:5];
      foreach (mem[i, j]) mem[i][j] = 31'(i);
      $readmemh(path("elem_a.hex"), mem[2]);
      `checkh(mem[2][2], 31'h11);
      `checkh(mem[2][5], 31'h14);
      `checkh(mem[1][2], 31'h1);
      `checkh(mem[3][5], 31'h3);
    end

    begin
      // Test: non-constant index, each row loaded by the same statement
      logic [6:0] mem[0:2][4];
      string files[2];
      files = '{"elem_a.hex", "elem_d.hex"};
      foreach (mem[i, j]) mem[i][j] = 7'h7f;
      for (int r = 0; r < two; ++r) $readmemh(path(files[r]), mem[r]);
      `checkh(mem[0][0], 7'h11);
      `checkh(mem[0][3], 7'h14);
      `checkh(mem[1][0], 7'h21);
      `checkh(mem[1][3], 7'h24);
      `checkh(mem[2][0], 7'h7f);
      `checkh(mem[2][3], 7'h7f);
    end

    begin
      // Test: index out of range leaves the array unchanged
      logic [6:0] mem[0:2][4];
      foreach (mem[i, j]) mem[i][j] = 7'h7f;
      $readmemh(path("elem_a.hex"), mem[three]);
      foreach (mem[i, j]) `checkh(mem[i][j], 7'h7f);
    end

    begin
      // Test: element of a class member and of a struct member
      typedef struct {
        int pad;
        logic [6:0] mem[2][4];
      } st_t;
      Cls obj;
      st_t st;
      obj = new;
      foreach (obj.mem[i, j]) obj.mem[i][j] = 7'h7f;
      foreach (st.mem[i, j]) st.mem[i][j] = 7'h7f;
      $readmemh(path("elem_a.hex"), obj.mem[one]);
      $readmemh(path("elem_d.hex"), st.mem[one]);
      `checkh(obj.mem[1][0], 7'h11);
      `checkh(obj.mem[1][3], 7'h14);
      `checkh(obj.mem[0][0], 7'h7f);
      `checkh(st.mem[1][0], 7'h21);
      `checkh(st.mem[1][3], 7'h24);
      `checkh(st.mem[0][3], 7'h7f);
    end

    begin
      // Test: element selected through this, in range and out of range
      Holder holder;
      holder = new;
      holder.load(path("elem_a.hex"), 2'(one));
      `checkh(holder.mem[1][0], 7'h11);
      `checkh(holder.mem[1][3], 7'h14);
      `checkh(holder.mem[0][0], 7'h7f);
      holder.load(path("elem_a.hex"), 2'(three));
      foreach (holder.mem[i, j]) `checkh(holder.mem[i][j], 7'h7f);
    end

    begin
      // Test: element of a 3-D array selected with two indices
      logic [14:0] cube[2][0:2][3:1];
      foreach (cube[i, j, k]) cube[i][j][k] = 15'h7fff;
      $readmemh(path("elem_t.hex"), cube[one][two]);
      `checkh(cube[1][2][1], 15'h31);
      `checkh(cube[1][2][3], 15'h33);
      `checkh(cube[1][1][1], 15'h7fff);
      `checkh(cube[0][2][3], 15'h7fff);
    end

    begin
      // Test: multi-dimensional element loads like a whole multi-dimensional variable
      logic [14:0] cube[2][0:2][3:1];
      logic [14:0] whole[0:2][3:1];
      foreach (cube[i, j, k]) cube[i][j][k] = 15'h7fff;
      foreach (whole[j, k]) whole[j][k] = 15'h7fff;
      $readmemh(path("elem_b.hex"), cube[one]);
      $readmemh(path("elem_b.hex"), whole);
      foreach (whole[j, k]) `checkh(cube[1][j][k], whole[j][k]);
      `checkh(cube[1][0][1], 15'h21);
      `checkh(cube[1][1][3], 15'h26);
      `checkh(cube[0][0][3], 15'h7fff);
    end

    begin
      // Test: $readmemb with start and end addresses leaves the rest of the element
      logic [6:0] mem[2][1:4];
      foreach (mem[i, j]) mem[i][j] = 7'h7f;
      $readmemb(path("elem_c.bin"), mem[one], 2, 3);
      `checkh(mem[1][1], 7'h7f);
      `checkh(mem[1][2], 7'b1010101);
      `checkh(mem[1][3], 7'b0101010);
      `checkh(mem[1][4], 7'h7f);
      `checkh(mem[0][2], 7'h7f);
    end

    begin
      // Test: typedef element, wide data
      typedef logic [64:0] row_t[2];
      row_t mem[3];
      foreach (mem[i, j]) mem[i][j] = '1;
      $readmemh(path("elem_w.hex"), mem[two]);
      `checkh(mem[2][0], 65'h1_0000_0001);
      `checkh(mem[2][1], 65'h1_0000_0002);
      `checkh(mem[1][1], {65{1'b1}});
    end

    begin
      // Test: dynamic, associative and queue forms
      logic [7:0] dyn_row[2][];
      logic [7:0] assoc_row[2][int];
      logic [7:0] dyn_of_fixed[][4];
      logic [7:0] queue_of_fixed[$][4];
      dyn_row[1] = new[4];
      $readmemh(path("elem_a.hex"), dyn_row[one]);
      `checkh(dyn_row[1][3], 8'h14);
      `checkh(dyn_row[0].size(), 0);
      $readmemh(path("elem_a.hex"), assoc_row[one]);
      `checkh(assoc_row[1][2], 8'h13);
      `checkh(assoc_row[0].num(), 0);
      dyn_of_fixed = new[2];
      foreach (dyn_of_fixed[i, j]) dyn_of_fixed[i][j] = 8'hff;
      $readmemh(path("elem_d.hex"), dyn_of_fixed[one]);
      `checkh(dyn_of_fixed[1][3], 8'h24);
      `checkh(dyn_of_fixed[0][3], 8'hff);
      queue_of_fixed.push_back('{default: 8'h00});
      queue_of_fixed.push_back('{default: 8'h00});
      $readmemh(path("elem_a.hex"), queue_of_fixed[one]);
      `checkh(queue_of_fixed[1][0], 8'h11);
      `checkh(queue_of_fixed[0][0], 8'h00);
    end

    begin
      // Test: $writememh of an element, whole and with an address range
      logic [6:0] mem[0:2][4];
      logic [6:0] back[4];
      foreach (mem[i, j]) mem[i][j] = 7'(i * 16 + j);
      $writememh(path("elem_o.hex"), mem[two]);
      $readmemh(path("elem_o.hex"), back);
      foreach (back[j]) `checkh(back[j], 7'(32 + j));
      $writememh(path("elem_p.hex"), mem[one], 1, 2);
      back = '{default: 7'h7f};
      $readmemh(path("elem_p.hex"), back, 1, 2);
      `checkh(back[0], 7'h7f);
      `checkh(back[1], 7'h11);
      `checkh(back[2], 7'h12);
      `checkh(back[3], 7'h7f);
    end

    begin
      // Test: $writememh of a slice and of an element of a slice
      logic [6:0] mem[3:0][0:3];
      logic [6:0] back[0:3];
      logic [6:0] back2[0:7];
      foreach (mem[i, j]) mem[i][j] = 7'(i * 16 + j);
      $writememh(path("elem_s.hex"), mem[2:1][one]);
      $readmemh(path("elem_s.hex"), back);
      foreach (back[j]) `checkh(back[j], 7'(16 + j));
      $writememh(path("elem_u.hex"), mem[2:1]);
      $readmemh(path("elem_u.hex"), back2);
      foreach (back2[j]) `checkh(back2[j], 7'(j < 4 ? 16 + j : 28 + j));
    end

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
