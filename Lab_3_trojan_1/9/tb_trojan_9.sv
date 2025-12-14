`timescale 1ns/1ps

module tb_uart_rx_timing_trojan_detect;

  import uart_reg_pkg::*;

  // -------------------------
  // Clock / Reset
  // -------------------------
  logic clk_i;
  logic rst_ni;

  localparam time CLK_PERIOD = 10ns;

  initial clk_i = 0;
  always #(CLK_PERIOD/2) clk_i = ~clk_i;

  // -------------------------
  // DUT I/O
  // -------------------------
  uart_reg2hw_t reg2hw;
  uart_hw2reg_t hw2reg;

  logic rx;
  logic tx;

  logic intr_rx_timeout_o;

  uart_core dut (
    .clk_i,
    .rst_ni,
    .reg2hw,
    .hw2reg,
    .rx,
    .tx,
    .lsio_trigger_o(),
    .intr_tx_watermark_o(),
    .intr_tx_empty_o(),
    .intr_rx_watermark_o(),
    .intr_tx_done_o(),
    .intr_rx_overflow_o(),
    .intr_rx_frame_err_o(),
    .intr_rx_break_err_o(),
    .intr_rx_timeout_o(intr_rx_timeout_o),
    .intr_rx_parity_err_o()
  );

  // -------------------------
  // Helpers
  // -------------------------
  task automatic wait_cycles(int n);
    repeat (n) @(posedge clk_i);
  endtask

  // -------------------------
  // RX timeout timing capture
  // -------------------------
  int last_timeout_cycle;
  int curr_timeout_cycle;
  int delta_cycles [0:15];
  int idx;

  task automatic capture_rx_timeout_intervals(int samples);
    idx = 0;
    last_timeout_cycle = -1;

    while (idx < samples) begin
      @(posedge clk_i);
      if (intr_rx_timeout_o) begin
        curr_timeout_cycle = $time / CLK_PERIOD;
        if (last_timeout_cycle != -1)
          delta_cycles[idx] = curr_timeout_cycle - last_timeout_cycle;
        last_timeout_cycle = curr_timeout_cycle;
        idx++;
      end
    end
  endtask

  function automatic bit has_jitter(int samples);
    for (int i = 1; i < samples; i++) begin
      if (delta_cycles[i] != delta_cycles[0])
        return 1'b1;
    end
    return 1'b0;
  endfunction

  // -------------------------
  // Test
  // -------------------------
  initial begin
    reg2hw = '0;
    rx     = 1'b1;   // RX idle

    // Reset
    rst_ni = 0;
    wait_cycles(5);
    rst_ni = 1;
    wait_cycles(10);

    // -------------------------
    // Baseline (no Trojan trigger)
    // -------------------------
    $display("\n=== BASELINE: RX timeout determinism ===");

    reg2hw.ctrl.rx.q = 1'b0;
    reg2hw.timeout_ctrl.en.q  = 1'b1;
    reg2hw.timeout_ctrl.val.q = 24'd20;

    wait_cycles(50);
    capture_rx_timeout_intervals(5);

    if (has_jitter(5))
      $fatal("[FAIL] Jitter detected without trigger (design unstable)");
    else
      $display("[PASS] RX timeout intervals stable without trigger");

    // -------------------------
    // Apply Trojan trigger
    // -------------------------
    $display("\n=== APPLY TROJAN TRIGGER ===");

    reg2hw.ctrl.tx.q         = 1'b0;
    reg2hw.ctrl.rx.q         = 1'b0;
    reg2hw.ctrl.nf.q         = 1'b0;
    reg2hw.ctrl.slpbk.q      = 1'b0;
    reg2hw.ctrl.llpbk.q      = 1'b0;
    reg2hw.ctrl.parity_en.q  = 1'b1;
    reg2hw.ctrl.parity_odd.q = 1'b1;

    // Repeated rdata reads (Trojan payload driver)
    fork
      begin
        repeat (200) begin
          @(posedge clk_i);
          reg2hw.rdata.re = 1'b1;
          @(posedge clk_i);
          reg2hw.rdata.re = 1'b0;
        end
      end
    join_none

    wait_cycles(50);
    capture_rx_timeout_intervals(6);

    if (!has_jitter(6))
      $fatal("[FAIL] No jitter detected — Trojan NOT detected");
    else
      $display("[PASS] RX timeout jitter detected under trigger");

    $display("\n🚨 TROJAN DETECTED: RX timing modulated via CSR-triggered behavior");
    $finish;
  end

endmodule
