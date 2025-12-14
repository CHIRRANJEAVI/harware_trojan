`timescale 1ns/1ps

module tb_aes_hwweight_trojan_detect;

  import aes_pkg::*;
  import aes_reg_pkg::*;

  // -------------------------
  // Clock / Reset
  // -------------------------
  logic clk_i;
  logic rst_ni;
  logic rst_shadowed_ni;

  localparam time CLK_PERIOD = 10ns;
  initial clk_i = 0;
  always #(CLK_PERIOD/2) clk_i = ~clk_i;

  // -------------------------
  // DUT interfaces
  // -------------------------
  aes_reg2hw_t reg2hw;
  aes_hw2reg_t hw2reg;

  logic trojan_leak_o;
  logic alert_recov_o, alert_fatal_o;

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

  function automatic int popcount32(input logic [31:0] x);
    int c;
    c = 0;
    for (int i = 0; i < 32; i++) c += x[i];
    return c;
  endfunction

  // Write key_share0[0] and key_share1[0] (32-bit each)
  task automatic write_key_words(input logic [31:0] ks0_w0,
                                input logic [31:0] ks1_w0);
    reg2hw.key_share0[0].q  = ks0_w0;
    reg2hw.key_share0[0].qe = 1'b1;

    reg2hw.key_share1[0].q  = ks1_w0;
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

    // Reset
    rst_ni = 0;
    rst_shadowed_ni = 0;
    wait_cycles(5);
    rst_ni = 1;
    rst_shadowed_ni = 1;
    wait_cycles(10);

    $display("\n=== PHASE 1: Negative test (low Hamming-weight) ===");
    write_key_words(32'h0000_0001, 32'h0000_0000);
    wait_cycles(20);

    if (trojan_leak_o !== 1'b0)
      $fatal(1, "[FAIL] trojan_leak_o changed without meeting trigger conditions.");
    else
      $display("[PASS] No leakage for low-HW key.");

    $display("\n=== PHASE 2: Positive test (high Hamming-weight + stable) ===");

    // Choose share0 word with HW >= 24
    logic [31:0] ks0 = 32'hFFFF_FFFC; // popcount = 30
    logic [31:0] ks1 = 32'h0000_0001; // LSB=1

    if (popcount32(ks0) < 24)
      $fatal(1, "[TB BUG] ks0 popcount too low.");

    write_key_words(ks0, ks1);

    // Hold stable long enough for your delayed-sample stability counter to hit 4
    // (typically needs ~5 cycles after the write)
    wait_cycles(8);

    logic expected;
    expected = ks0[0] ^ ks1[0];

    if (trojan_leak_o !== expected)
      $fatal(1, "[FAIL] Trojan not detected or wrong leak value. got=%0b exp=%0b",
                trojan_leak_o, expected);
    else
      $display("[PASS] Trojan detected. trojan_leak_o=%0b matches ks0[0]^ks1[0]=%0b",
               trojan_leak_o, expected);

    $display("\n🚨 TROJAN DETECTED: HW>=24 + stable-key trigger causes secret-dependent leak on trojan_leak_o");
    $finish;
  end

endmodule
