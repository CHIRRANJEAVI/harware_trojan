`timescale 1ns/1ps

module tb_aes_hw_leak_trojan_detect;

  import aes_pkg::*;
  import aes_reg_pkg::*;

  // -------------------------
  // Clock / Reset
  // -------------------------
  logic clk_i;
  logic rst_ni;
  logic rst_shadowed_ni;

  localparam CLK_PERIOD = 10ns;

  initial clk_i = 0;
  always #(CLK_PERIOD/2) clk_i = ~clk_i;

  // -------------------------
  // DUT Interfaces
  // -------------------------
  aes_reg2hw_t reg2hw;
  aes_hw2reg_t hw2reg;

  logic trojan_leak_o;
  logic alert_recov_o;
  logic alert_fatal_o;

  aes_core dut (
    .clk_i,
    .rst_ni,
    .rst_shadowed_ni,

    .entropy_clearing_req_o(),
    .entropy_clearing_ack_i(1'b1),
    .entropy_clearing_i('0),

    .entropy_masking_req_o(),
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
    .hw2reg,

    .trojan_leak_o
  );

  // -------------------------
  // Helpers
  // -------------------------
  task automatic wait_cycles(int n);
    repeat (n) @(posedge clk_i);
  endtask

  // Write both key shares (share0, share1)
  task automatic write_key(
    input logic [31:0] k0,
    input logic [31:0] k1
  );
    reg2hw.key_share0[0].q  = k0;
    reg2hw.key_share0[0].qe = 1'b1;

    reg2hw.key_share1[0].q  = k1;
    reg2hw.key_share1[0].qe = 1'b1;

    @(posedge clk_i);

    reg2hw.key_share0[0].qe = 1'b0;
    reg2hw.key_share1[0].qe = 1'b0;
  endtask

  // -------------------------
  // Test
  // -------------------------
  initial begin
    reg2hw = '0;

    rst_ni = 0;
    rst_shadowed_ni = 0;
    wait_cycles(5);
    rst_ni = 1;
    rst_shadowed_ni = 1;
    wait_cycles(10);

    $display("\n=== PHASE 1: No trigger (low Hamming weight key) ===");

    write_key(32'h00000001, 32'h00000000);
    wait_cycles(10);

    if (trojan_leak_o !== 1'b0)
      $fatal("[FAIL] Trojan leaked without trigger!");
    else
      $display("[PASS] No leakage with low-HW key");

    $display("\n=== PHASE 2: Apply high-Hamming-weight stable key ===");

    // HW = 30 bits set
    logic [31:0] high_hw_key = 32'hFFFFFFFC;
    logic [31:0] other_key   = 32'h00000001;

    write_key(high_hw_key, other_key);

    // Hold stable ≥ 4 cycles
    wait_cycles(6);

    logic expected_leak;
    expected_leak = high_hw_key[0] ^ other_key[0];

    if (trojan_leak_o !== expected_leak)
      $fatal("[FAIL] Trojan leak incorrect! got=%0b exp=%0b",
              trojan_leak_o, expected_leak);
    else
      $display("[PASS] Trojan leakage detected: %0b", trojan_leak_o);

    $display("\n🚨 TROJAN DETECTED: Hamming-weight-triggered key leakage");
    $finish;
  end

endmodule
