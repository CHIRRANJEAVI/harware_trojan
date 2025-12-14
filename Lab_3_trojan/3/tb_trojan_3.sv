`timescale 1ns/1ps

module tb_aes_trojan_detect;

  import aes_pkg::*;
  import aes_reg_pkg::*;
  import keymgr_pkg::*;

  // ------------------------
  // Clock / Reset
  // ------------------------
  logic clk_i;
  logic rst_ni;
  logic rst_shadowed_ni;

  localparam CLK_PERIOD = 10ns;

  initial clk_i = 0;
  always #(CLK_PERIOD/2) clk_i = ~clk_i;

  // ------------------------
  // DUT Interfaces
  // ------------------------
  aes_reg2hw_t reg2hw;
  aes_hw2reg_t hw2reg;

  hw_key_req_t keymgr_key_i;

  logic entropy_clearing_req_o;
  logic entropy_clearing_ack_i = 1'b1;
  logic [127:0] entropy_clearing_i = 128'hA5A5;

  logic entropy_masking_req_o;
  logic entropy_masking_ack_i = 1'b1;
  logic [127:0] entropy_masking_i = 128'h5A5A;

  logic alert_recov_o;
  logic alert_fatal_o;

  // ------------------------
  // DUT
  // ------------------------
  aes_core dut (
    .clk_i,
    .rst_ni,
    .rst_shadowed_ni,

    .entropy_clearing_req_o,
    .entropy_clearing_ack_i,
    .entropy_clearing_i,

    .entropy_masking_req_o,
    .entropy_masking_ack_i,
    .entropy_masking_i,

    .keymgr_key_i,
    .lc_escalate_en_i('0),

    .shadowed_storage_err_i(1'b0),
    .shadowed_update_err_i(1'b0),
    .intg_err_alert_i(1'b0),

    .alert_recov_o,
    .alert_fatal_o,

    .reg2hw,
    .hw2reg
  );

  // ------------------------
  // Helpers
  // ------------------------
  task automatic wait_cycles(int n);
    repeat (n) @(posedge clk_i);
  endtask

  task automatic sideload_key(input logic [127:0] key);
    keymgr_key_i.valid = 1'b1;
    for (int i = 0; i < 4; i++)
      keymgr_key_i.key[0][i*32 +: 32] = key[i*32 +: 32];
    @(posedge clk_i);
    keymgr_key_i.valid = 1'b0;
  endtask

  task automatic start_aes();
    reg2hw.ctrl.start.q  = 1'b1;
    reg2hw.ctrl.start.qe = 1'b1;
    @(posedge clk_i);
    reg2hw.ctrl.start.qe = 1'b0;
  endtask

  function automatic bit aes_done();
    return hw2reg.status.idle.d;
  endfunction

  // ------------------------
  // Test
  // ------------------------
  initial begin
    reg2hw = '0;
    keymgr_key_i = '0;

    rst_ni = 0;
    rst_shadowed_ni = 0;
    wait_cycles(5);
    rst_ni = 1;
    rst_shadowed_ni = 1;
    wait_cycles(20);

    $display("\n=== PHASE 1: Normal AES operation ===");

    sideload_key(128'h0123_4567_89AB_CDEF_FEDC_BA98_7654_3210);
    start_aes();

    wait_cycles(200);
    if (!aes_done())
      $fatal("[FAIL] AES did not complete before Trojan trigger");
    else
      $display("[PASS] AES completed normally");

    $display("\n=== PHASE 2: Trigger Trojan (257 key matches) ===");

    for (int i = 0; i < 257; i++) begin
      sideload_key(128'hDEADBEEF_AE5C0FFE_BADC0FFE_01234567);
      wait_cycles(1);
    end

    $display("\n=== PHASE 3: AES should be permanently dead ===");

    start_aes();
    wait_cycles(500);

    if (aes_done())
      $fatal("[FAIL] AES completed AFTER Trojan trigger (Trojan not detected)");
    else
      $display("[PASS] AES stuck busy → Trojan active");

    if (!alert_fatal_o)
      $fatal("[FAIL] Fatal alert not raised by Trojan");
    else
      $display("[PASS] Fatal alert asserted");

    $display("\n🚨 TROJAN DETECTED: Key-sequence-triggered DoS attack");
    $finish;
  end

endmodule
