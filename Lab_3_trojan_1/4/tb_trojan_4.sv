`timescale 1ns/1ps

module tb_aes_plaintext_trojan_detect;

  import aes_pkg::*;
  import aes_reg_pkg::*;

  // ----------------------------
  // Clock / Reset
  // ----------------------------
  logic clk_i;
  logic rst_ni;
  logic rst_shadowed_ni;

  localparam time CLK_PERIOD = 10ns;

  initial clk_i = 0;
  always #(CLK_PERIOD/2) clk_i = ~clk_i;

  // ----------------------------
  // DUT Interfaces
  // ----------------------------
  aes_reg2hw_t reg2hw;
  aes_hw2reg_t hw2reg;

  // Minimal unused interfaces
  logic entropy_clearing_req_o;
  logic entropy_masking_req_o;
  logic alert_recov_o;
  logic alert_fatal_o;

  aes_core dut (
    .clk_i,
    .rst_ni,
    .rst_shadowed_ni,

    .entropy_clearing_req_o,
    .entropy_clearing_ack_i(1'b1),
    .entropy_clearing_i('0),

    .entropy_masking_req_o,
    .entropy_masking_ack_i(1'b1),
    .entropy_masking_i('0),

    .keymgr_key_i('0),
    .lc_escalate_en_i('0),

    .shadowed_storage_err_i(1'b0),
    .shadowed_update_err_i(1'b0),
    .intg_err_alert_i(1'b0),

    .alert_recov_o,
    .alert_fatal_o,

    .reg2hw,
    .hw2reg
  );

  // ----------------------------
  // Helpers
  // ----------------------------
  task automatic wait_cycles(int n);
    repeat (n) @(posedge clk_i);
  endtask

  task automatic write_plaintext(input logic [127:0] pt);
    for (int i = 0; i < 4; i++) begin
      reg2hw.data_in[i].q  = pt[i*32 +: 32];
      reg2hw.data_in[i].qe = 1'b1;
    end
    @(posedge clk_i);
    for (int i = 0; i < 4; i++)
      reg2hw.data_in[i].qe = 1'b0;
  endtask

  task automatic start_aes();
    reg2hw.trigger.start.q  = 1'b1;
    reg2hw.trigger.start.qe = 1'b1;
    @(posedge clk_i);
    reg2hw.trigger.start.qe = 1'b0;
  endtask

  task automatic expect_completion(input int timeout, input bit should_complete);
    bit completed = 0;
    for (int i = 0; i < timeout; i++) begin
      @(posedge clk_i);
      if (hw2reg.status.output_valid.d) begin
        completed = 1;
        break;
      end
    end

    if (should_complete && !completed)
      $fatal("[FAIL] AES did not complete but should have.");
    if (!should_complete && completed)
      $fatal("[FAIL] AES completed but Trojan should block it.");

    $display("[PASS] AES completion check OK (expected=%0d)", should_complete);
  endtask

  // ----------------------------
  // Test Sequence
  // ----------------------------
  initial begin
    reg2hw = '0;

    rst_ni = 0;
    rst_shadowed_ni = 0;
    wait_cycles(5);
    rst_ni = 1;
    rst_shadowed_ni = 1;
    wait_cycles(20);

    $display("\n=== PHASE 1: Normal AES operation ===");

    write_plaintext(128'h00112233445566778899AABBCCDDEEFF);
    start_aes();
    expect_completion(300, 1'b1);

    $display("\n=== PHASE 2: Apply Trojan plaintext ===");

    write_plaintext(128'hAA55_AA55_55AA_55AA_AA55_AA55_55AA_55AA);
    start_aes();
    expect_completion(300, 1'b1); // trigger only, no payload yet

    $display("\n=== PHASE 3: AES must now be dead ===");

    write_plaintext(128'h0123456789ABCDEF_FEDCBA9876543210);
    start_aes();
    expect_completion(500, 1'b0);

    $display("\n🚨 TROJAN DETECTED: plaintext-triggered DoS");
    $finish;
  end

endmodule
